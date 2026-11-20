#ifndef HHHS_LIBS_ESPFC_OUTPUT_OUTPUTIBUS_HPP_
#define HHHS_LIBS_ESPFC_OUTPUT_OUTPUTIBUS_HPP_

#include "Stream/ReadWritable.hpp"
#include "Utils/Timer.hpp"

namespace Espfc::Output {

class OutputIBUS
{
public:
  OutputIBUS();

  int begin(Stream::ReadWritable* serial);
  int update();

private:
  Stream::ReadWritable* _serial;
  Utils::Timer _timer;
};

} // namespace Espfc::Output
#endif // HHHS_LIBS_ESPFC_OUTPUT_OUTPUTIBUS_HPP_
