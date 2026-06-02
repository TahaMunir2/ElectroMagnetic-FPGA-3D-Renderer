// Until real readouts arrive from the PS (/registers) we fake them here.
// Swapping to real data later touches ONLY this file.
export function mockReadouts() {
  return {
    fps: 0,
    timestep: 0,
    throughput: 0,   // MPix/s
    cpuFps: 0,       // CPU baseline, for comparison
  };
}
