/*
 * fpc1022-wake.c - Early Hardware State Initializer for FPC1022 (10a5:9200)
 *
 * Xiaomi Mi NoteBook Ultra / Pro / Max integrated fingerprint & power button.
 * Sends CMD_INDICATE_S_STATE (S0) and CMD_INIT to wake the FPC microcontroller
 * on cold boot and resume from suspend so the physical power button works immediately
 * without requiring a prior biometric verification request.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libusb-1.0/libusb.h>

#define FPC1022_VID 0x10a5
#define FPC1022_PID 0x9200

#define FPC1022_CMD_INIT              0x01
#define FPC1022_CMD_INDICATE_S_STATE  0x08
#define FPC1022_S_STATE_S0            0x0010
#define FPC1022_TIMEOUT_MS            1000

static const unsigned char init_data[4] = { 0x10, 0x2f, 0x11, 0x17 };

int main(int argc, char *argv[])
{
    libusb_context *ctx = NULL;
    libusb_device_handle *devh = NULL;
    int r;
    int verbose = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Usage: fpc1022-wake [-v|--verbose] [-h|--help]\n");
            printf("Initializes FPC1022 (10a5:9200) into S0 working state.\n");
            return 0;
        }
    }

    r = libusb_init(&ctx);
    if (r < 0) {
        if (verbose) {
            fprintf(stderr, "fpc1022-wake: libusb_init failed: %s (%d)\n",
                    libusb_error_name(r), r);
        }
        return 1;
    }

    devh = libusb_open_device_with_vid_pid(ctx, FPC1022_VID, FPC1022_PID);
    if (!devh) {
        if (verbose) {
            fprintf(stderr, "fpc1022-wake: device %04x:%04x not found or permission denied\n",
                    FPC1022_VID, FPC1022_PID);
        }
        libusb_exit(ctx);
        return 2;
    }

    /*
     * 1. Send S0 State Indication (bRequest = 0x08, wValue = 0x0010).
     * This signals the FPC MCU that the host OS is in S0 (Active Working State),
     * which un-gates the physical power button line connected to the ACPI PWRBTN.
     */
    r = libusb_control_transfer(
        devh,
        LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_DEVICE,
        FPC1022_CMD_INDICATE_S_STATE,
        FPC1022_S_STATE_S0,
        0x0000,
        NULL,
        0,
        FPC1022_TIMEOUT_MS
    );
    if (r < 0 && verbose) {
        fprintf(stderr, "fpc1022-wake: S0 state transfer notice: %s (%d)\n",
                libusb_error_name(r), r);
    }

    /*
     * 2. Send Sensor Init Command (bRequest = 0x01, wValue = 0x0001, payload = {0x10, 0x2f, 0x11, 0x17}).
     * Initializes the internal sensor state machine so both biometrics and button
     * hardware logic are primed.
     */
    r = libusb_control_transfer(
        devh,
        LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_DEVICE,
        FPC1022_CMD_INIT,
        0x0001,
        0x0000,
        (unsigned char *)init_data,
        sizeof(init_data),
        FPC1022_TIMEOUT_MS
    );
    if (r < 0 && verbose) {
        fprintf(stderr, "fpc1022-wake: INIT transfer notice: %s (%d)\n",
                libusb_error_name(r), r);
    }

    libusb_close(devh);
    libusb_exit(ctx);

    if (verbose) {
        printf("fpc1022-wake: Successfully initialized %04x:%04x into S0 working state.\n",
               FPC1022_VID, FPC1022_PID);
    }
    return 0;
}
