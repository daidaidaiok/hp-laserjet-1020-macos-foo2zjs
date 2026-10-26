/*
 * sc-deviceid: ask the CUPS backend for the printer's IEEE 1284 device ID
 * over the side channel and print it to stdout.
 *
 * Only works when run as a CUPS filter (the side channel is fd 4).
 * Exit status: 0 = ID printed, 1 = side channel unavailable or failed.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <cups/sidechannel.h>
#include <stdio.h>

int main(void)
{
    char buf[2048];
    int len = sizeof(buf) - 1;
    cups_sc_status_t status;

    status = cupsSideChannelDoRequest(CUPS_SC_CMD_GET_DEVICE_ID, buf, &len, 5.0);
    if (status != CUPS_SC_STATUS_OK || len <= 0)
        return 1;

    buf[len] = '\0';
    puts(buf);
    return 0;
}
