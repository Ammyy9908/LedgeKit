# Timer: an example add-on

A countdown beside the notch, showing live activities (LedgeKit 0.10.0):

- `AddOnSession.show(activities:)` with a pinned countdown (progress ring) and a "done" activity that lasts five
  seconds. An empty list takes them down.
- `onActivityPlacement`: Ledge's own activities always come first. The timer shows its placement on its page, stops
  sending while the user has turned its activities off, and if it ends unseen it also sends `LedgeHost.notify`.
- A settings page with a picker, a button and a status value; the length is kept with `LedgeHost.set`.

Build it with `swift build -c release --package-path Examples/Timer`, then put the `Timer` binary next to
`addon.json` in a folder named `Timer.ledgeaddon` and load it in Ledge (Add-on Store › ••• › Load Add-on…).
