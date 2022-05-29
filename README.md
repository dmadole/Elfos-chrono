# Chrono

This is a loadable RTC-72421 clock driver for Elf/OS for the 1802/Mini expander card. This provides the standard o_gettod and o_settod calls for getting and setting the time.

Note that the standard date program in Elf/OS only calls BIOS and not the newer kernel hooks for these calls and to cannot work with this driver. You can use the updated date program here:

https://github.com/dmadole/Elfos-date

This is build by default for the RTC on port 5 with no group select.

As an alternative, you can use in-BIOS support for the expander card, which does not require any software support and also supports expanded memory:

https://github.com/dmadole/1802-Mini/tree/master/firmware

