#ifndef HHHS_LIBS_ESPFC_UTILS_FILTERHELPER_HPP_
#define HHHS_LIBS_ESPFC_UTILS_FILTERHELPER_HPP_

#include "Utils/Filter.hpp"
#include <helper_3dmath.hpp>

namespace Espfc::Utils {

float applyFilter(Filter& filter, float sample);

VectorFloat applyFilter(Filter filters[3], const VectorFloat& samples);

} // namespace Espfc::Utils
#endif // HHHS_LIBS_ESPFC_UTILS_FILTERHELPER_HPP_
