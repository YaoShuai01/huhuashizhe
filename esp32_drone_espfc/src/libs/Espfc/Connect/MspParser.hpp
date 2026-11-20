#ifndef HHHS_LIBS_ESPFC_CONNECT_MSPPARSER_HPP_
#define HHHS_LIBS_ESPFC_CONNECT_MSPPARSER_HPP_

#include "Connect/Msp.hpp"

namespace Espfc::Connect {

class MspParser
{
public:
  MspParser();
  void parse(char c, MspMessage& msg);
};

} // namespace Espfc::Connect
#endif // HHHS_LIBS_ESPFC_CONNECT_MSPPARSER_HPP_
