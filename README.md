> [!NOTE]
> The repository's documentation website: [**slayhorizon.github.io/godot-tiny-mmo/**](https://slayhorizon.github.io/godot-tiny-mmo/)  
> Latest research note: [**Byte-Level Networking Protocol for MMO Scalability**](https://slayhorizon.github.io/godot-tiny-mmo/#/pages/notes/next_level)

[![Godot Engine](https://img.shields.io/badge/Godot-4.4+-blue?logo=godot-engine)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://img.shields.io/badge/docs-website-blue.svg)](https://slayhorizon.github.io/godot-tiny-mmo/)

# Godot Tiny MMO

**Experimental open-source MMORPG framework** built with **Godot 4**.  
Inspired by proven MMO systems, this project pushes the boundaries of what can be achieved with Godot in large-scale multiplayer.  
It explores scalable multiplayer architecture, efficient byte-packed networking, while staying clear and simple in our learning journey.

- **Cross-platform**: browser + desktop + mobile
- **Unified codebase**: Client & multiple servers in one repo
  - Faster iteration, develop in one place, test in one click
  - Separate export presets for clean client/server builds 
- **"Custom netcode"** but stay simple  
  - No reliance on Godot’s `MultiplayerSynchronizer/Spawner` for better control
  - Packed protocol format (efficient PackedByteArray instead of string-based messages) for hot synchronization
  - Entity interpolation, multi-map instances, seamless transitions
- **True MMOO architecture**
  - **Gateway server**: authentication & routing
  - **Master server**: orchestrator, account management & bridge between gateways and world servers
  - **World server**: host multiple concurrent maps and instances; the place where gameplay actually happens

---

## Screenshots

<details>
<summary>See screenshots:</summary>
   
![architecture-diagram](https://github.com/user-attachments/assets/78b1cce2-b070-4544-8ecd-59784743c7a0)
<img width="1813" height="985" alt="image" src="https://github.com/user-attachments/assets/216a946e-26f5-4829-886e-5b58e323f9c8" />
<img width="1718" height="573" alt="image" src="https://github.com/user-attachments/assets/cdd8da32-be03-4a9b-a93d-0d83858a086c" />

</details>

---

## Features

<details>
<summary>See current and planned features:</summary>

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
- [x] **Weapons** at least one usable weapon per class
- [x] **Basic combat system**

- [X] **Entity synchronization** for players within the same instance
- [ ] **Entity interpolation** to handle rubber banding
- [x] **Instance-based chat** for localized communication
- [X] **Instance-based maps** with traveling between different map instances
   - [x] **Three different maps:** Overworld, Dungeon Entrance, Dungeon
   - [ ] **Private instances** for solo players or small groups
- [ ] **Server-side anti-cheat** (basic validation for speed hacks, teleport hacks, etc.)
- [x] **Server-side NPCs** (AI logic processed on the server)

</details>

---

## Getting Started

To run the project, follow these steps:

1. Open the project in **Godot 4.4 or 4.5**.
2. Go to Debug tab, select **"Customizable Run Instance..."**.
3. Enable **Multiple Instances** and set the count to **4 or more**.
4. Under **Feature Tags**, ensure you have:
   - Exactly **one** "gateway-server" tag.
   - Exactly **one** "master-server" tag.
   - Exactly **one** "world-server" tag.
   - At least **one or more** "client" tags.
5. (Optional) Under **Launch Arguments**:
   - For servers, add **--headless** to prevent empty windows.
   - For any, add **--config=config_file_path.cfg** to use non-default config path.
6. Run the project (Press F5).

Setup example 
(More details in the wiki [How to use "Customize Run Instances..."](https://slayhorizon.github.io/godot-tiny-mmo/#/pages/customize_run_instances):
<img width="1580" alt="debug-screenshot" src="https://github.com/user-attachments/assets/cff4dd67-00f2-4dda-986f-7f0bec0a695e">

---

## Contributing

Feel free to fork the repository and submit a pull request if you have ideas or improvements!  
You can also open an [**Issue**](https://github.com/SlayHorizon/godot-tiny-mmo/issues) to discuss bugs or feature requests.

---

## Credits

Thanks to everyone who made this project possible:
- **Maps** designed by [@higaslk](https://github.com/higaslk)
- Valuable help and feedback: [@Jackiefrost](https://github.com/Jackietkfrost), [@d-Cadrius](https://github.com/d-Cadrius) and multiple anonymous contributors
- Also [@Anokolisa](https://anokolisa.itch.io/dungeon-crawler-pixel-art-asset-pack) for allowing us to use its assets for this open source project!

## License
Source code under the [MIT License](https://github.com/SlayHorizon/godot-tiny-mmo/blob/main/LICENSE).
