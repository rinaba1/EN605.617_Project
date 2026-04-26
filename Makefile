NVCC = nvcc
NVCCFLAGS = -std=c++17 -O2 -arch=sm_75 -Isrc

all: golf_sim

golf_sim: src/golf_sim.cu src/golf_sim.h
	$(NVCC) $(NVCCFLAGS) -o golf_sim src/golf_sim.cu

clean:
	rm -f golf_sim
