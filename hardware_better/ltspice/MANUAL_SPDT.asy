Version 4
SymbolType CELL
LINE Normal -32 0 -8 0
LINE Normal -8 0 20 -24
LINE Normal 28 -32 40 -32
LINE Normal 28 32 40 32
CIRCLE Normal -12 -4 -4 4
CIRCLE Normal 20 -36 28 -28
CIRCLE Normal 20 28 28 36
TEXT -36 48 Left 1 SPDT
WINDOW 0 -32 -64 Left 2
WINDOW 3 -32 64 Left 2
SYMATTR Prefix X
SYMATTR Value MANUAL_SPDT
SYMATTR SpiceLine STATE=0
SYMATTR ModelFile ManualSwitch.lib
SYMATTR Description Manual SPDT switch. STATE=0 left pin to 0, STATE=1 left pin to 1.
PIN -64 0 LEFT 8
PINATTR SpiceOrder 1
PIN 64 -32 RIGHT 8
PINATTR PinName 1
PINATTR SpiceOrder 2
PIN 64 32 RIGHT 8
PINATTR PinName 0
PINATTR SpiceOrder 3
