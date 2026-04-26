# Monte Carlo Golf Shot Simulator

Runs a Monte Carlo golf shot trajectory simulation using CUDA. Exports landing points and metadata to output files, and results are plotted using `scripts/plot_dispersion.py`.

## Environment Setup

- Make sure `nvcc` is installed
- Python 3 is required to run the plotting script (`scripts/plot_dispersion.py`)

Using a virtual environment is recommended:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
pip install -r requirements.txt
```

## Build and Run

```bash
make
./golf_sim <sim_id> <ball_speed_mph> <launch_angle_deg> <backspin_rpm> <sidespin_rpm> <target_dist_yds> <target_radius_yds> [seed]
python3 scripts/plot_dispersion.py --sim-id <id>
```

Or use **`bash scripts/run_pipeline.sh`**

## Limitations

- **Simplified drag/magnus**: dimples on the golf balls are not accounted for.
- **Constant wind per shot**; it doesn't account for any gusts along the trajectory.
- **Uses carry distance only**: it only checks whether the landing point is inside the target radius (no bounce/roll after landing)

## References

- Golf Ball Flight Dynamics: `https://www.math.union.edu/~wangj/courses/previous/math238w13/Golf%20Ball%20Flight%20Dynamics2.pdf`
