#ifndef HHHS_LIBS_GPS_GPSPARSER_HPP_
#define HHHS_LIBS_GPS_GPSPARSER_HPP_

#include "GpsProtocol.hpp"
#include <cstdint>

namespace Gps {

class UbxParser
{
public:
  void parse(uint8_t c, UbxMessage& m);
};

class NmeaParser
{
public:
  void parse(uint8_t c, NmeaMessage& m);
};

} // namespace Gps
#endif // HHHS_LIBS_GPS_GPSPARSER_HPP_
