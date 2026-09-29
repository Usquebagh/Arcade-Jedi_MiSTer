// Verilator testbench for jedi_core: runs N frames and dumps selected frames as PPM.
// Usage: Vjedi_core <frames> <dump_every> [test]
//   test = hold the self-test switch on (service mode)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vjedi_core.h"
#include "verilated.h"

static const int W = 296, H = 240;

static void write_ppm(const char *name, const std::vector<uint8_t> &fb) {
    FILE *f = fopen(name, "wb");
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    fwrite(fb.data(), 1, fb.size(), f);
    fclose(f);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int frames = argc > 1 ? atoi(argv[1]) : 60;
    int every  = argc > 2 ? atoi(argv[2]) : 10;
    bool test  = argc > 3 && !strcmp(argv[3], "test");

    Vjedi_core *top = new Vjedi_core;
    top->in0   = test ? 0xef : 0xff;   // all switches released; b4 = /self-test
    top->tilt  = 0;
    top->adc_x = 0x80;
    top->adc_y = 0x80;

    std::vector<uint8_t> fb(W * H * 3, 0);
    int frame = 0;
    bool last_vblank = false;
    uint64_t cycles = 0;

    top->reset = 1;
    for (int i = 0; i < 200; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
    top->reset = 0;

    while (frame < frames) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cycles++;

        if (!top->ce_pix) continue;
        if (!top->hblank && !top->vblank && top->vid_h < W && top->vid_v < H) {
            uint8_t *p = &fb[(top->vid_v * W + top->vid_h) * 3];
            p[0] = top->red; p[1] = top->green; p[2] = top->blue;
        }
        if (top->vblank && !last_vblank) {
            frame++;
            printf("frame %4d  main AB %04x  snd AB %04x  outlatch %02x\n",
                   frame, top->dbg_main_ab, top->dbg_snd_ab, top->dbg_outlatch);
            if (frame % every == 0) {
                char name[64];
                snprintf(name, sizeof name, "frame_%04d.ppm", frame);
                write_ppm(name, fb);
            }
        }
        last_vblank = top->vblank;
    }

    printf("%llu clocks, %.2f s emulated\n", (unsigned long long)cycles, cycles / 48.384e6);
    delete top;
    return 0;
}
