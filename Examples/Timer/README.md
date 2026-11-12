# Timer: an example add-on

A countdown in every place an add-on can show something (LedgeKit 0.11.0):

- `AddOnSession.show(activities:)` with a pinned countdown (progress ring) and a "done" activity that lasts five
  seconds. An empty list takes them down.
- `onActivityPlacement`: Ledge's own activities always come first. The timer shows its placement on its page, stops
  sending while the user has turned its activities off, and if it ends unseen it also sends `LedgeHost.notify`.
- `show(lockScreenRow:)`: the time left in a pill under the clock while the Mac is locked; nil takes it down.
- `show(menuBarTiles:)`: a row in the menu bar panel that starts the timer or shows the time left and stops it;
  a click arrives in `onEvent` with `surface` `menu-bar-tile`.
- A settings page with a picker, a button and a status value; the length is kept with `LedgeHost.set`.

Build it with `swift build -c release --package-path Examples/Timer`, then put the `Timer` binary next to
`addon.json` in a folder named `Timer.ledgeaddon` and load it in Ledge (Add-on Store › ••• › Load Add-on…).
