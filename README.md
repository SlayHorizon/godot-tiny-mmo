> [!WARNING]  
> This project is in **experimental state**, and some features are missing (See [**# Features**](#features)).  

# Godot Tiny MMO

A tiny web-based MMORPG demo developed with Godot Engine 4.x - 4.4,  
created without relying on the built-in multiplayer nodes.  

The client and server share the same codebase,  
but custom export presets allow you to [**Export Client and Server builds separately**](https://github.com/SlayHorizon/godot-tiny-mmo-demo/wiki/Exporting-the-project),  
keeping builds safe and optimized by excluding unnecessary components.

For additional details, check out the [**Wiki**](https://github.com/SlayHorizon/godot-tiny-mmo-demo/wiki).  

![project-demo-screenshot](https://github.com/user-attachments/assets/ca606976-fd9d-4a92-a679-1f65cb80513a)
![image](https://github.com/user-attachments/assets/7e21a7e5-4c72-4871-b0cf-6d94f8931bf7)


## Features

Current and planned features:

- [X] **Client-Server connection** through `WebSocketMultiplayerPeer`
- [x] **Playable on web browser and desktop**
- [x] **Network architecture** (see diagram below)
- [X] **Authentication system** through gateway server with Login UI
- [x] **Account Creation** for permanent player accounts
- [x] **Server Selection UI** to let the player choose between different servers
- [x] **QAD Database** to save persistent data
- [x] **Guest Login** option for quick access
- [x] **Game version check** to ensure client compatibility
- [x] **Character Creation**
- [x] **Basic RPG class system** with three initial classes: Knight, Rogue, Wizard
- [ ] **Weapons** at least one usable weapon per class
- [ ] **Basic combat system**
- [X] **Entity synchronization** for players within the same instance
- [ ] **Entity interpolation** to handle rubber banding
- [x] **Instance-based chat** for localized communication
- [X] **Instance-based maps** with traveling between different map instances
- [x] **Three different maps:** Overworld, Dungeon Entrance, Dungeon
- [ ] **Private instances** for solo players or small groups
- [ ] **Server-side anti-cheat** (basic validation for speed hacks, teleport hacks, etc.)
- [ ] **Server-side NPCs** (AI logic processed on the server)

Current network architecture diagram for this demo (subject to change):  
![architecture-diagram-26-10-2024](https://github.com/user-attachments/assets/78b1cce2-b070-4544-8ecd-59784743c7a0)

## 🛠️ Getting Started

To run the project:, follow these steps:

1. Open the project in **Godot 4.3+**.
2. Go to Debug tab, select **"Customizable Run Instance..."**.
3. Enable **Multiple Instances** and set the count to **4 or more**.
4. Under **Feature Tags**, ensure you have:
   - Exactly **one** "gateway-server" tag.
   - Exactly **one** "master-server" tag.
   - Exactly **one** "world-server" tag.
   - At least **one or more** "client" tags
5. (Optional) Under **Launch Arguments**:
   - For servers, add **--headless** to prevent empty windows.
   - For any, add **--config=config_file_path.cfg** to use non-default config path. 
6. Run the project (Press F5)

Setup example:  
(More details in the wiki [How to use "Customize Run Instances..."](https://github.com/SlayHorizon/godot-tiny-mmo/wiki/How-to-use-%22Customize-Run-Instances...%22#customize-run-instances))
<img width="1580" alt="debug-screenshot" src="https://github.com/user-attachments/assets/cff4dd67-00f2-4dda-986f-7f0bec0a695e">
  

## Contributing

If you have ideas or improvements, feel free to fork this repository and submit a pull request.  
You can also open an [**Issue**](https://github.com/SlayHorizon/godot-tiny-mmo-template/issues) with the tag `enhancement` to talk about it, same for bug reports but with the tag `bug`.

## Credits
- Maps designed by [@d-Cadrius](https://github.com/d-Cadrius).
- Screenshots provided by [@WithinAmnesia](https://github.com/WithinAmnesia).  
- Also thanks to [@Anokolisa](https://anokolisa.itch.io/dungeon-crawler-pixel-art-asset-pack) for allowing us to use its assets for this open source project!

> _For inquiries, contact me on Discord: `slayhorizon`_
