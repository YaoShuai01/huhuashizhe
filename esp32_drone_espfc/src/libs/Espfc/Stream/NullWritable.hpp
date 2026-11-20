#ifndef HHHS_LIBS_ESPFC_STREAM_NULLWRITABLE_HPP_
#define HHHS_LIBS_ESPFC_STREAM_NULLWRITABLE_HPP_

#include "Stream/Writable.hpp"

namespace Espfc::Stream {

// Null Writable that discards all data.
class NullWritable : public Writable
{
public:
  size_t write(uint8_t c) override
  {
    return 1;
  }

  size_t write(const uint8_t* data, size_t len) override
  {
    return len;
  }

  int availableForWrite() override
  {
    return 0;
  }

  void flush() override {}

  bool isTxFifoEmpty() override
  {
    return true;
  }
};

} // namespace Espfc::Stream
#endif // HHHS_LIBS_ESPFC_STREAM_NULLWRITABLE_HPP_
