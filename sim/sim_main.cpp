// Verilator testbench for jedi_core: runs N frames and dumps selected frames as PPM.
// Usage: Vjedi_core <frames> <dump_every> [test]
//   test = hold the self-test switch on (service mode)
// Environment:
//   DUMP_FROM=n          also dump every frame from n on
//   INPUTS=f:v,f:v,...   from frame f, drive the 0C00 switch byte with hex value v
//   YOKE=f:x:y,...       from frame f, drive the ADC X/Y values (hex)
// Audio is written to audio.raw (signed 16-bit mono, 48 kHz).
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
    int from   = getenv("DUMP_FROM") ? atoi(getenv("DUMP_FROM")) : 1 << 30;   // dump every frame from here

    Vjedi_core *top = new Vjedi_core;
    top->in0   = test ? 0xef : 0xff;   // all switches released; b4 = /self-test
    top->tilt  = 0;
    top->adc_x = 0x80;
    top->adc_y = 0x80;

    // Input script
    std::vector<std::pair<int, int>> script;
    if (const char *s = getenv("INPUTS")) {
        int f, v, n;
        while (sscanf(s, "%d:%x%n", &f, &v, &n) == 2) {
            script.push_back({f, v});
            s += n;
            if (*s == ',') s++;
        }
    }
    size_t next_input = 0;

    struct YokeStep { int frame, x, y; };
    std::vector<YokeStep> yoke;
    if (const char *s = getenv("YOKE")) {
        int f, x, y, n;
        while (sscanf(s, "%d:%x:%x%n", &f, &x, &y, &n) == 3) {
            yoke.push_back({f, x, y});
            s += n;
            if (*s == ',') s++;
        }
    }
    size_t next_yoke = 0;

    FILE *audio = fopen("audio.raw", "wb");
    int64_t audio_acc = 0;
    uint32_t audio_n = 0;

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

        // 48 kHz audio: 48.384 MHz / 1008, box-filtered
        audio_acc += (int16_t)top->audio;
        if (++audio_n == 1008) {
            int16_t s = (int16_t)(audio_acc / 1008);
            fwrite(&s, 2, 1, audio);
            audio_acc = audio_n = 0;
        }

        if (!top->ce_pix) continue;
        if (!top->hblank && !top->vblank && top->vid_h < W && top->vid_v < H) {
            uint8_t *p = &fb[(top->vid_v * W + top->vid_h) * 3];
            p[0] = top->red; p[1] = top->green; p[2] = top->blue;
        }
        if (top->vblank && !last_vblank) {
            frame++;
            while (next_input < script.size() && script[next_input].first <= frame)
                top->in0 = script[next_input++].second;
            while (next_yoke < yoke.size() && yoke[next_yoke].frame <= frame) {
                top->adc_x = yoke[next_yoke].x;
                top->adc_y = yoke[next_yoke].y;
                next_yoke++;
            }
            printf("frame %4d  main AB %04x  snd AB %04x  outlatch %02x\n",
                   frame, top->dbg_main_ab, top->dbg_snd_ab, top->dbg_outlatch);
            if (frame % every == 0 || frame >= from) {
                char name[64];
                snprintf(name, sizeof name, "frame_%04d.ppm", frame);
                write_ppm(name, fb);
            }
        }
        last_vblank = top->vblank;
    }

    fclose(audio);
    printf("%llu clocks, %.2f s emulated\n", (unsigned long long)cycles, cycles / 48.384e6);
    delete top;
    return 0;
}
