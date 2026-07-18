#ifndef MACOS_UI_H
#define MACOS_UI_H

#ifdef __APPLE__

#include "SDL.h"

double macos_ui_saved_scale(void);
const char *macos_ui_disk_path(int drive);
void macos_ui_init(SDL_Window *window);

#endif

#endif
