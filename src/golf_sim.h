#ifndef GOLF_SIM_H
#define GOLF_SIM_H

#include <cuda_runtime.h>

struct LandingPoint {
	// landing point in yards (x = lateral, z = downrange)
	float lateral_yds;
	float downrange_yds;
};

struct LaunchInput {
	int simulation_id{};
	float ball_speed_mph{};
	float launch_angle_deg{};
	float backspin_rpm{};
	float sidespin_rpm{};
	float target_dist_yds{};
	float target_radius_yds{};
	int rng_seed{};
};

// constants (SI unless noted)
static const float PI = 3.1415926535f;
static const float AIR_DENSITY = 1.225f;				// kg/m^3
static const float BALL_MASS = 0.0459f;					// kg
static const float BALL_CROSS_SECTION_AREA = 0.001432f; // m^2
static const float DRAG_COEFFICIENT = 0.24f;
static const float MAGNUS_LIFT_COEFFICIENT = 0.16f;
static const float GRAVITY_MS2 = -9.81f; // m/s^2

// unit conversions
static const float MPH_TO_METERS_PER_SEC = 0.44704f;
static const float METERS_TO_YARDS = 1.09361f;

// integration
static const float SIM_TIME_STEP = 0.005f; // seconds
static const float TEE_HEIGHT_METERS = 0.01f;
static const float MIN_AIR_REL_SPEED = 0.1f;	   // m/s
static const float MAX_DOWNRANGE_METERS = 1500.0f; // m

// Monte Carlo jitter spans
static const float LAUNCH_SPEED_JITTER_RANGE =
	0.06f; // +/-3% on launch speed components
static const float SPIN_RATE_JITTER_RANGE = 0.10f; // +/-5% on back/side spin

// launch-plane rotation span (degrees)
static const float LAUNCH_ANGLE_JITTER_RANGE_DEG = 2.0f;

// horizontal aim rotation span about +y (degrees)
static const float HORIZONTAL_AIM_JITTER_RANGE_DEG = 4.0f;

// wind component spans (m/s)
static const float WIND_CROSSWIND_SPAN_MS = 8.0f;
static const float WIND_VERTICAL_SPAN_MS = 1.5f;
static const float WIND_DOWNRANGE_SPAN_MS = 6.0f;

// CUDA setting
static const int NUM_MONTE_CARLO_SHOTS = 100000;
static const int CUDA_THREADS_PER_BLOCK = 256;

static const float RPM_TO_RADIANS_PER_SEC = (2.0f * PI) / 60.0f;

#endif
