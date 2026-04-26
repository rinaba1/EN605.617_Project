// Monte carlo golf-ball flight simulation (one trajectory per thread)
// writes landing points to output/csv and run metadata to output/json

#include "golf_sim.h"

#include <cmath>
#include <curand_kernel.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

__global__ void simulateShot(LandingPoint *landing_points,
							 float3 base_launch_velocity_mps,
							 float3 base_spin_rad_s, int num_shots,
							 int rng_seed) {

	const int tid = blockIdx.x * blockDim.x + threadIdx.x;

	if (tid >= num_shots) {
		return;
	}

	curandState rng;
	curand_init(rng_seed, tid, 0, &rng);

	// constant wind per shot
	const float3 wind_mps =
		make_float3((curand_uniform(&rng) - 0.5f) * WIND_CROSSWIND_SPAN_MS,
					(curand_uniform(&rng) - 0.5f) * WIND_VERTICAL_SPAN_MS,
					(curand_uniform(&rng) - 0.5f) * WIND_DOWNRANGE_SPAN_MS);

	// per-shot multipliers (ball strike variability)
	const float launch_speed_scale =
		1.0f + (curand_uniform(&rng) - 0.5f) * LAUNCH_SPEED_JITTER_RANGE;
	const float spin_rate_scale =
		1.0f + (curand_uniform(&rng) - 0.5f) * SPIN_RATE_JITTER_RANGE;

	// speed scale + launch-angle jitter in the y-z plane
	float v_up_mps = base_launch_velocity_mps.y * launch_speed_scale;
	float v_downrange_mps = base_launch_velocity_mps.z * launch_speed_scale;
	const float launch_angle_offset_rad =
		(curand_uniform(&rng) - 0.5f) *
		(LAUNCH_ANGLE_JITTER_RANGE_DEG * (PI / 180.0f));
	const float cos_launch_offset = cosf(launch_angle_offset_rad);
	const float sin_launch_offset = sinf(launch_angle_offset_rad);
	const float launch_v_up_mps =
		v_up_mps * cos_launch_offset - v_downrange_mps * sin_launch_offset;
	const float launch_v_downrange_mps =
		v_up_mps * sin_launch_offset + v_downrange_mps * cos_launch_offset;

	// horizontal aim error: rotate x-z about +y
	const float aim_error_rad =
		(curand_uniform(&rng) - 0.5f) *
		(HORIZONTAL_AIM_JITTER_RANGE_DEG * (PI / 180.0f));
	const float cos_aim = cosf(aim_error_rad);
	const float sin_aim = sinf(aim_error_rad);
	const float v_lateral_mps = base_launch_velocity_mps.x * launch_speed_scale;
	const float launch_v_lateral_mps =
		v_lateral_mps * cos_aim + launch_v_downrange_mps * sin_aim;
	const float launch_v_downrange_after_aim_mps =
		-v_lateral_mps * sin_aim + launch_v_downrange_mps * cos_aim;

	float3 position_m = make_float3(0.0f, TEE_HEIGHT_METERS, 0.0f);
	float3 velocity_mps = make_float3(launch_v_lateral_mps, launch_v_up_mps,
									  launch_v_downrange_after_aim_mps);
	float3 spin_rad_s =
		make_float3(base_spin_rad_s.x * spin_rate_scale,
					base_spin_rad_s.y * spin_rate_scale,
					base_spin_rad_s.z); // spin (rad/s): z remains unchanged

	while (position_m.y > 0.0f) {
		const float rel_vx = velocity_mps.x - wind_mps.x;
		const float rel_vy = velocity_mps.y - wind_mps.y;
		const float rel_vz = velocity_mps.z - wind_mps.z;
		const float air_rel_speed_sq =
			rel_vx * rel_vx + rel_vy * rel_vy + rel_vz * rel_vz;
		const float inv_air_speed = rsqrtf(air_rel_speed_sq);
		const float air_rel_speed = air_rel_speed_sq * inv_air_speed;
		if (air_rel_speed < MIN_AIR_REL_SPEED) {
			break;
		}

		const float drag_force_magnitude = 0.5f * AIR_DENSITY *
										   air_rel_speed_sq * DRAG_COEFFICIENT *
										   BALL_CROSS_SECTION_AREA;
		const float3 force_drag_n =
			make_float3(-rel_vx * inv_air_speed * drag_force_magnitude,
						-rel_vy * inv_air_speed * drag_force_magnitude,
						-rel_vz * inv_air_speed * drag_force_magnitude);

		// magnus lift (quadratic lift law): direction omega x v_rel
		float3 force_magnus_n =
			make_float3(spin_rad_s.y * rel_vz - spin_rad_s.z * rel_vy,
						spin_rad_s.z * rel_vx - spin_rad_s.x * rel_vz,
						spin_rad_s.x * rel_vy - spin_rad_s.y * rel_vx);

		const float magnus_cross_len_sq = force_magnus_n.x * force_magnus_n.x +
										  force_magnus_n.y * force_magnus_n.y +
										  force_magnus_n.z * force_magnus_n.z;
		if (magnus_cross_len_sq > 0.0f) {
			const float magnus_cross_len = sqrtf(magnus_cross_len_sq);
			const float magnus_lift_magnitude =
				0.5f * AIR_DENSITY * air_rel_speed_sq *
				MAGNUS_LIFT_COEFFICIENT * BALL_CROSS_SECTION_AREA;
			const float magnus_normalize_scale =
				magnus_lift_magnitude / magnus_cross_len;
			force_magnus_n.x *= magnus_normalize_scale;
			force_magnus_n.y *= magnus_normalize_scale;
			force_magnus_n.z *= magnus_normalize_scale;
		}

		// Newton's 2nd law (plus gravity in +y)
		const float accel_x_mps2 =
			(force_drag_n.x + force_magnus_n.x) / BALL_MASS;
		const float accel_y_mps2 =
			GRAVITY_MS2 + (force_drag_n.y + force_magnus_n.y) / BALL_MASS;
		const float accel_z_mps2 =
			(force_drag_n.z + force_magnus_n.z) / BALL_MASS;

		// semi-implicit Euler: update v, then x using the updated v
		velocity_mps.x += accel_x_mps2 * SIM_TIME_STEP;
		velocity_mps.y += accel_y_mps2 * SIM_TIME_STEP;
		velocity_mps.z += accel_z_mps2 * SIM_TIME_STEP;

		position_m.x += velocity_mps.x * SIM_TIME_STEP;
		position_m.y += velocity_mps.y * SIM_TIME_STEP;
		position_m.z += velocity_mps.z * SIM_TIME_STEP;

		if (position_m.z > MAX_DOWNRANGE_METERS) {
			break;
		}
	}

	// landing in yards (x = lateral, z = downrange)
	landing_points[tid].lateral_yds = position_m.x * METERS_TO_YARDS;
	landing_points[tid].downrange_yds = position_m.z * METERS_TO_YARDS;
}

struct LaunchInput {
	int simulation_id{};
	float ball_speed_mph{};
	float launch_angle_deg{};
	float backspin_rpm{};
	float sidespin_rpm{};
	float target_dist_yds{};
	float target_radius_yds{};
};

static bool parse_args(int argc, char **argv, LaunchInput &out) {
	if (argc != 8) {
		return false;
	}
	try {
		out.simulation_id = std::stoi(argv[1]);
		out.ball_speed_mph = std::stof(argv[2]);
		out.launch_angle_deg = std::stof(argv[3]);
		out.backspin_rpm = std::stof(argv[4]);
		out.sidespin_rpm = std::stof(argv[5]);
		out.target_dist_yds = std::stof(argv[6]);
		out.target_radius_yds = std::stof(argv[7]);
	} catch (...) {
		return false;
	}
	return true;
}

// nominal launch velocity (m/s): y up, z downrange
static float3 computeNominalLaunchVelocityMps(float ball_speed_mph,
											  float launch_angle_deg) {
	const float speed_mps = ball_speed_mph * MPH_TO_METERS_PER_SEC;
	const float angle_rad = launch_angle_deg * (PI / 180.0f);
	return make_float3(0.0f, speed_mps * sinf(angle_rad),
					   speed_mps * cosf(angle_rad));
}

// nominal spin (rad/s): backspin is -x, sidespin is +y
static float3 computeNominalSpinRadPerSec(float backspin_rpm,
										  float sidespin_rpm) {
	return make_float3(-backspin_rpm * RPM_TO_RADIANS_PER_SEC,
					   sidespin_rpm * RPM_TO_RADIANS_PER_SEC, 0.0f);
}

int main(int argc, char **argv) {
	LaunchInput input{};
	if (!parse_args(argc, argv, input)) {
		return 1;
	}

	const float3 nominal_launch_velocity_mps = computeNominalLaunchVelocityMps(
		input.ball_speed_mph, input.launch_angle_deg);
	const float3 nominal_spin_rad_s =
		computeNominalSpinRadPerSec(input.backspin_rpm, input.sidespin_rpm);

	const int num_shots = NUM_MONTE_CARLO_SHOTS;
	LandingPoint *d_landing_points = nullptr;
	cudaMalloc(&d_landing_points, (size_t)num_shots * sizeof(LandingPoint));

	const int threads_per_block = CUDA_THREADS_PER_BLOCK;
	const int num_blocks =
		(num_shots + threads_per_block - 1) / threads_per_block;
	simulateShot<<<num_blocks, threads_per_block>>>(
		d_landing_points, nominal_launch_velocity_mps, nominal_spin_rad_s,
		num_shots, input.simulation_id);
	cudaDeviceSynchronize();

	std::vector<LandingPoint> landings_yards((size_t)num_shots);
	cudaMemcpy(landings_yards.data(), d_landing_points,
			   (size_t)num_shots * sizeof(LandingPoint),
			   cudaMemcpyDeviceToHost);

	double sum_carry_yds = 0.0;
	double sum_lateral_yds = 0.0;
	int num_hits = 0;

	// output directories
	std::filesystem::create_directories("output/csv");
	std::filesystem::create_directories("output/json");

	// export simulation results to CSV
	const std::string results_csv =
		"output/csv/results_sim" + std::to_string(input.simulation_id) + ".csv";

	std::ofstream out(results_csv);
	out << "lateral_yds,carry_yds\n";

	for (int i = 0; i < num_shots; ++i) {
		const float lateral_yds = landings_yards[i].lateral_yds;
		const float carry_yds = landings_yards[i].downrange_yds;
		sum_carry_yds += carry_yds;
		sum_lateral_yds += lateral_yds;
		out << lateral_yds << ',' << carry_yds << '\n';

		// hit test in landing plane
		const float downrange_error_yds = carry_yds - input.target_dist_yds;
		const float distance_to_target_center =
			sqrtf(lateral_yds * lateral_yds +
				  downrange_error_yds * downrange_error_yds);
		if (distance_to_target_center <= input.target_radius_yds) {
			++num_hits;
		}
	}

	std::cout << "\nSimulation ID: " << input.simulation_id << "\n";
	std::cout << "Avg Carry: " << (sum_carry_yds / num_shots) << " yds | "
			  << "Avg Lateral: " << (sum_lateral_yds / num_shots) << " yds\n";
	std::cout << "Hits in Target: "
			  << (100.0f * (float)num_hits / (float)num_shots) << "%\n";

	// export run metadata to JSON
	const std::string run_json =
		"output/json/run_sim" + std::to_string(input.simulation_id) + ".json";
	{
		std::ofstream jf(run_json);
		jf << "{\n";
		jf << "  \"simulation_id\": " << input.simulation_id << ",\n";
		jf << "  \"ball_speed_mph\": " << input.ball_speed_mph << ",\n";
		jf << "  \"launch_angle_deg\": " << input.launch_angle_deg << ",\n";
		jf << "  \"backspin_rpm\": " << input.backspin_rpm << ",\n";
		jf << "  \"sidespin_rpm\": " << input.sidespin_rpm << ",\n";
		jf << "  \"target_dist_yds\": " << input.target_dist_yds << ",\n";
		jf << "  \"target_radius_yds\": " << input.target_radius_yds << ",\n";
		jf << "  \"num_shots\": " << num_shots << "\n";
		jf << "}\n";
	}

	std::cout << "Exported results to " << results_csv << " and " << run_json
			  << "\n";

	cudaFree(d_landing_points);
	return 0;
}
