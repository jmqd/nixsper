# nixsper

Nixsper is a simple nix service package for enabling usage of whisper-large-v3
as a background service to live-transcribe your voice. The daemon accepts START
and STOP commands, which can be sent to the socket at `65432` to initiate or
close voice transcription.

I use it in my nixos config like so:

```
  services.nixsper.enable = true;
```

I personally configure my ~/.config/i3/config like so, using echo and netcat:

``` sh
bindsym $mod+Shift+w exec echo "START" | nc -N 127.0.0.1 65432
bindsym $mod+Shift+s exec echo "STOP" | nc -N 127.0.0.1 65432
```

Then, when I do SUPER + Shift + w, my text is auto-transcribed at point using
`xdotool`. SUPER + Shift + s stops transcription.
