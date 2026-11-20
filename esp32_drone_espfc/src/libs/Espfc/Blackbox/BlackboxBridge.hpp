#ifndef HHHS_LIBS_ESPFC_BLACKBOX_BLACKBOXBRIDGE_HPP_
#define HHHS_LIBS_ESPFC_BLACKBOX_BLACKBOXBRIDGE_HPP_

#include "Model.hpp"
#include <platform.h>
extern "C" {
#include <blackbox/blackbox.h>
#include <blackbox/blackbox_fielddefs.h>
bool blackboxShouldLogPFrame(void);
bool blackboxShouldLogIFrame(void);
}

void initBlackboxModel(Espfc::Model* m);
#endif // HHHS_LIBS_ESPFC_BLACKBOX_BLACKBOXBRIDGE_HPP_
