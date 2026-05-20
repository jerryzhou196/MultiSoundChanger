<p align="center">
  <img width="350" height="276" src="https://user-images.githubusercontent.com/8312717/115996670-e6511000-a5e8-11eb-8c46-869378d4df2a.png">
</p>

## MultiSound Changer for MacOS
Latest release https://github.com/rlxone/MultiSoundChanger/releases

A small tool for changing sound volume **even for aggregate devices** cause native sound volume controller can't change volume of aggregate devices (it was always pain in the ass with my laptop).
 


Features:
* **Changing sound volume of every device** (even virtual aggregate device volume by changing volume of every device in aggregate device)
* **Per-device boost offsets** — each output device gets a "Boost" slider in the menu that adds a constant volume offset on top of the master level, useful for compensating when one speaker in an aggregate device is naturally louder or quieter than the others
* Changing default output device
* Native appearance (looks like native volume controller)
* Media keys support

I think it can be very useful if you're using VoodooHDA with 4.0+ sound on the board (my use case), but you can find another use cases.

## Per-device Boost

When you have an aggregate device combining multiple speakers, they often have different natural loudness levels. The boost slider (shown below each device in the menu) lets you dial in a constant offset (0–100%) that is added to that device's volume whenever the master level is set — so all your speakers stay balanced relative to each other.

## Usage

For example if you want to play 2 or more output devices at the same time you should:
* Create aggregate device in Audio MIDI Setup
* Add all output devices you want to this new aggregate device
* Hide default sound controller icon if enabled (by dragging away or in audio preferences)
* Use our app to control sound volume
* Add our app to startup (if you need)


## Inspiration
* [retrography/audioswitch](https://github.com/retrography/audioswitch)

## Licence
* This project is released under the Apache 2.0 licence. See LICENCE
