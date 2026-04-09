NVCC = nvcc
NVCCFLAGS = -std=c++17 -O2 -arch=sm_75

all: golf_sim

golf_sim: golf_sim.cu golf_sim.h
	$(NVCC) $(NVCCFLAGS) -o golf_sim golf_sim.cu

clean:
	rm -f golf_sim
