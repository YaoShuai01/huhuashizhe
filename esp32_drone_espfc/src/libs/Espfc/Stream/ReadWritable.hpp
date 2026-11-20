#ifndef HHHS_LIBS_ESPFC_STREAM_READWRITABLE_HPP_
#define HHHS_LIBS_ESPFC_STREAM_READWRITABLE_HPP_

#include "Hal/Serial.hpp"
#include "Stream/Readable.hpp"
#include "Stream/Writable.hpp"

namespace Espfc::Stream {

// Bidirectional byte stream.
class ReadWritable : public Readable, public Writable
{
public:
  virtual void begin(const Hal::SerialDeviceConfig& config) = 0;
  virtual void updateBaudRate(int baud) = 0;

protected:
  ~ReadWritable() = default;
};

} // namespace Espfc::Stream
#endif // HHHS_LIBS_ESPFC_STREAM_READWRITABLE_HPP_
