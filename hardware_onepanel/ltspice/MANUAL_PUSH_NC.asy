Version 4
SymbolType CELL
LINE Normal -32 8 -8 8
LINE Normal 8 8 32 8
LINE Normal -8 8 8 8
LINE Normal -12 -24 12 -24
LINE Normal 0 -24 0 -8
CIRCLE Normal -12 4 -4 12
CIRCLE Normal 4 4 12 12
TEXT -34 32 Left 1 PUSH NC
WINDOW 0 -32 -56 Left 2
WINDOW 3 -32 48 Left 2
SYMATTR Prefix X
SYMATTR Value MANUAL_PUSH_NC
SYMATTR SpiceLine PRESS=0
SYMATTR ModelFile ManualSwitch.lib
SYMATTR Description Manual normally-closed push button. PRESS=0 released, PRESS=1 pressed.
PIN -64 8 LEFT 8
PINATTR PinName a
PINATTR SpiceOrder 1
PIN 64 8 RIGHT 8
PINATTR PinName b
PINATTR SpiceOrder 2
