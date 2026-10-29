# PinchPoint

Pinch and Point to control your macs mouse.

## Using PinchPoint

The installation of PinchPoint is as easy as any other application on macos, you open the dmg and then you drag and drop the app into Applications. Running is a bit annoying cause macOS flags the app as not signed and downloaded from the internet, to still open it you will have to navigate to the privacy section in settings and click open on the app.
If during installation macOS marks the app file as corrupt/broken issue this command from the terminal to "fix" the app: ```xattr -cr /Path/To/The/App.app```
> Note: PinchPoint requires macOS 26 or a later version

When the app is running you can simple put up your hand in front of the camera and the proram will automatically start tracking. The tracking is not perfect, for the best results it is recommended to have a not so distracting background and ensure good lighting in the room. The tracking may not lock to your hand at first, if so try to turn your hand around until the cursor starts moving.

## How it works

The program takes each frame the camera produces and passes it through Apples Vision model. That model takes out multiple joints from that frame which the program then translates to cursor movement or clicks.
