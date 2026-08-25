# Fields of Multiplayer

A Multiplayer mod for Fields of Mistria https://www.fieldsofmistria.com/ using two components,
- a relay https://github.com/DeUloO/Fields-of-Multiplayer-Relay
- and the GML mod (this repo)

loaded into the game using MOMI(MMAPI) https://github.com/Garethp/Mods-of-Mistria-Installer/.
The relay is necessary since the GML code is running on a GM VM (Fabricator https://github.com/kyren/fabricator/) in which the only way to communicate outside is through writing to and reading from the same folder as where the game puts its saves folder and crash logs.

Any and all contributions and bug fixes are welcome, you may add your name to the manifest.json if you so wish.
As a general rule: People will NOT be added to the Nexus mod as contributors due to safety concerns (since I am telling people to use a .exe file).
