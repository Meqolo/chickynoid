# Chickynoid

A server-authoritative networking character controller for Roblox.

Maintained and written by MrChickenRocket and Brooke.

**Massive Work In Progress**
Fair warning, this is not ready for production in it's current form.
Feel free to have a look at it and see how it does what it does, though!


**What is it?**
Chickynoid is intended to be a replacement for roblox "humanoid" based characters. 
It consists of the chickynoid character controller, a character 'renderer' (TBD), and a framework on the client and server for managing player connections and network replication. 


**What does it do?**

Chickynoid heavily borrows from the same principals that games like quake, cod, overwatch, and other first person shooters use to prevent fly hacking, teleporting, and other "typical" character hacks that roblox is typically vulnerable to.

It implements a full character controller and character physics using nothing but raycasts (Spherecast when pls roblox?), and trusts nothing from the client except input directions and buttons (and to a limited degree dt).

It implements "rollback" style networking on the client, so if the server disagrees about the results of your input, the client corrects to where it should be based on the remaining unconfirmed input.

**What are the benefits**

Players can't move cheat with this. At all*
The version of the chickynoid on the server is ground-truth, so its perfect for doing server-side checks for touching triggers and other gameplay uses that humanoid isn't good at.
The chickynoid player controller code is fairly straightforward. 
Turn speed, braking, max speed, "step up size" and acceleration are much easier to tune than in default roblox.



**How does it do it?**

TBD! 





**What are the drawbacks?**

Building a character out of a sphere shape is generally a poor idea - rounded bottoms don't handle steps well, and the "belly" has to be handled if it catches on ledges.

The sweepcast module is **slow** and somewhat janky.

This doesn't replace even a significant subset of what 



**Whats todo**

Buffer underrun detection "Antiwarp" (so technically freezing your character is still possible right now)

Delta time validation (so technically speed cheating is still possible right now)

Character rendering (we dont replicate the avatar yet)


