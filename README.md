#PinchPoint

Pinch and Point to control your macs mouse.

## Using PinchPoint

The installation of PinchPoint is as easy as any other application on macos, you drag and drop the file into Applications. Running is a bit annoying cause macOS flags the app as not signed and downloaded from the internet, to still open it you will have to navigate to the privacy section in settings and click open on the app.

When the app is running you can simple put up your hand in front of the camera and the proram will automatically start tracking. The tracking is not perfect, for the best results it is recommended to have a not so distracting background and not being in a dark place. It may not lock on at first, if not try to turn your hand around until the cursor starts moving.

## How it works

The program takes each frame the camera produces and passes it through Apples Vision model. That model takes out multiple joints from that frame which the program then translates to cursor movement or clicks.
