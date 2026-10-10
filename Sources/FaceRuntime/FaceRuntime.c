#include "FaceRuntime.h"
#include "onnxruntime_c_api.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

typedef struct {
    void *library;
    const OrtApi *api;
    OrtEnv *env;
    OrtSession *session;
    OrtMemoryInfo *memory;
    float *inputBuffer;
    OrtValue *inputTensor;
    char input[128], output[128];
} Model;
static int check(Model *m, OrtStatus *status, char *error, size_t size) {
    if (!status) return 1;
    snprintf(error, size, "%s", m->api->GetErrorMessage(status));
    m->api->ReleaseStatus(status); return 0;
}
void WDDestroyFaceModel(void *ptr) {
    Model *m = ptr; if (!m) return;
    if (m->api) {
        if (m->inputTensor) m->api->ReleaseValue(m->inputTensor);
        if (m->memory) m->api->ReleaseMemoryInfo(m->memory);
        if (m->session) m->api->ReleaseSession(m->session);
        if (m->env) m->api->ReleaseEnv(m->env);
    }
    // Keep runtime loaded: its process-global worker/destructor state outlives a session.
    free(m->inputBuffer); free(m);
}
void *WDCreateFaceModel(const char *library, const char *path, char *error, size_t size) {
    Model *m = calloc(1, sizeof(Model));
    m->library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!m->library) { snprintf(error,size,"%s",dlerror()); free(m); return NULL; }
    const OrtApiBase *(*base)(void) = dlsym(m->library,"OrtGetApiBase");
    if (!base || !(m->api = base()->GetApi(ORT_API_VERSION))) {
        snprintf(error,size,"ONNX Runtime API unavailable"); WDDestroyFaceModel(m); return NULL;
    }
    OrtSessionOptions *options = NULL;
    if (!check(m,m->api->CreateEnv(ORT_LOGGING_LEVEL_ERROR,"WindowDoor",&m->env),error,size)) goto failure;
    if (!check(m,m->api->DisableTelemetryEvents(m->env),error,size)) goto failure;
    if (!check(m,m->api->CreateSessionOptions(&options),error,size)) goto failure;
    if (!check(m,m->api->SetIntraOpNumThreads(options,2),error,size)) goto failure;
    if (!check(m,m->api->SetInterOpNumThreads(options,1),error,size)) goto failure;
    if (!check(m,m->api->AddSessionConfigEntry(options,"session.intra_op.allow_spinning","0"),error,size)) goto failure;
    if (!check(m,m->api->AddSessionConfigEntry(options,"session.inter_op.allow_spinning","0"),error,size)) goto failure;
    if (!check(m,m->api->SetSessionGraphOptimizationLevel(options,ORT_ENABLE_ALL),error,size)) goto failure;
    if (!check(m,m->api->CreateSession(m->env,path,options,&m->session),error,size)) goto failure;
    m->api->ReleaseSessionOptions(options); options = NULL;
    OrtAllocator *allocator = NULL; char *name = NULL;
    if (!check(m,m->api->GetAllocatorWithDefaultOptions(&allocator),error,size)) goto failure;
    if (!check(m,m->api->SessionGetInputName(m->session,0,allocator,&name),error,size)) goto failure;
    snprintf(m->input,sizeof(m->input),"%s",name); allocator->Free(allocator,name); name = NULL;
    if (!check(m,m->api->SessionGetOutputName(m->session,0,allocator,&name),error,size)) goto failure;
    snprintf(m->output,sizeof(m->output),"%s",name); allocator->Free(allocator,name);
    if (!check(m,m->api->CreateCpuMemoryInfo(OrtArenaAllocator,OrtMemTypeDefault,&m->memory),error,size)) goto failure;
    m->inputBuffer = calloc(112*112*3, sizeof(float));
    if (!m->inputBuffer) { snprintf(error,size,"Input allocation failed"); goto failure; }
    int64_t dimensions[] = {1,3,112,112};
    if (!check(m,m->api->CreateTensorWithDataAsOrtValue(m->memory,m->inputBuffer,112*112*3*sizeof(float),dimensions,4,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,&m->inputTensor),error,size)) goto failure;
    return m;
failure:
    if (options) m->api->ReleaseSessionOptions(options);
    WDDestroyFaceModel(m); return NULL;
}
int WDExtractFace(void *ptr, const uint8_t *rgb, float *embedding, size_t capacity, char *error, size_t size) {
    Model *m = ptr; if (!m || !rgb) return 0;
    const size_t pixels = 112 * 112;
    float *input = m->inputBuffer;
    for (size_t i=0;i<pixels;i++) for (size_t channel=0;channel<3;channel++) input[channel*pixels+i] = rgb[i*3+channel];
    OrtValue *output = NULL;
    OrtTensorTypeAndShapeInfo *info = NULL;
    int count = 0;
    const char *inputs[] = {m->input}, *outputs[] = {m->output};
    const OrtValue *values[] = {m->inputTensor};
    if (!check(m,m->api->Run(m->session,NULL,inputs,values,1,outputs,1,&output),error,size)) goto cleanup;
    if (!check(m,m->api->GetTensorTypeAndShape(output,&info),error,size)) goto cleanup;
    size_t n = 0;
    if (!check(m,m->api->GetTensorShapeElementCount(info,&n),error,size)) goto cleanup;
    if (n>capacity || n==0) { snprintf(error,size,"Invalid embedding size: %zu",n); goto cleanup; }
    float *result = NULL;
    if (!check(m,m->api->GetTensorMutableData(output,(void**)&result),error,size)) goto cleanup;
    double squared = 0;
    for (size_t i=0;i<n;i++) { if (!isfinite(result[i])) goto cleanup; squared += result[i]*result[i]; }
    if (squared<1e-12) goto cleanup;
    for (size_t i=0;i<n;i++) embedding[i]=result[i]/sqrt(squared);
    count=(int)n;
cleanup:
    if (info) m->api->ReleaseTensorTypeAndShapeInfo(info);
    if (output) m->api->ReleaseValue(output);
    return count;
}
