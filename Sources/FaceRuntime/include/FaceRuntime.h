#ifndef WINDOW_DOOR_FACE_RUNTIME_H
#define WINDOW_DOOR_FACE_RUNTIME_H
#include <stddef.h>
#include <stdint.h>
void *WDCreateFaceModel(const char *library, const char *model, char *error, size_t capacity);
int WDExtractFace(void *model, const uint8_t *rgb112, float *embedding, size_t capacity, char *error, size_t errorCapacity);
void WDDestroyFaceModel(void *model);
#endif
