#ifndef HHHS_LIBS_AHRS_COMPLEMENTARY_HPP_
#define HHHS_LIBS_AHRS_COMPLEMENTARY_HPP_

// complementary filter for fusing rate and position measurements
class Complementary
{
public:
  void begin(float sampleRate, float tau, float state = 0.0f);
  float update(float rate, float position);

private:
  float _dt{0.001f};
  float _alpha{0.998f};
  float _state{0.0f};
};
#endif // HHHS_LIBS_AHRS_COMPLEMENTARY_HPP_
