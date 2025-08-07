> [!NOTE]
> The repository's documentation website: [**slayhorizon.github.io/godot-tiny-mmo/**](https://slayhorizon.github.io/godot-tiny-mmo/)

[![Godot Engine](https://img.shields.io/badge/Godot-4.4+-blue?logo=godot-engine)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://img.shields.io/badge/docs-website-blue.svg)](https://slayhorizon.github.io/godot-tiny-mmo/)

# Godot Tiny MMO

A tiny, **experimental** MMORPG demo developed with **Godot Engine 4.4**.

- **Browser + Desktop support**  
- **Shared codebase**  
  - Client and server live in the same repo  
  - Clear folder organization  
  - Faster iteration: develop & test in one place  
- **Optimized exports** 
  - Separate presets for client & server  
  - Excludes unused components (e.g. no server logic in client)  
- **"Custom" netcode**  
  - No MultiplayerSynchronizer/Spawner  
  - Supports movement interpolation, multiple maps loaded simultaneously, etc.  
- **Mimic real MMO-style architecture**  
  - **Gateway server**: authentication & routing  
  - **Master server**: account management & bridge between gateways and world servers  
  - **World servers**: host multiple map instances per server

---

## Screenshots

<details>
<summary>See screenshots:</summary>
   
![project-demo-screenshot](https://github.com/user-attachments/assets/ca606976-fd9d-4a92-a679-1f65cb80513a)
![image](https://github.com/user-attachments/assets/7e21a7e5-4c72-4871-b0cf-6d94f8931bf7)
![architecture-diagram](https://github.com/user-attachments/assets/78b1cce2-b070-4544-8ecd-59784743c7a0)

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

</details>

---

## Getting Started

To run the project, follow these steps:

1. Open the project in **Godot 4.4**.
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
You can also open an [**Issue**](https://github.com/SlayHorizon/godot-tiny-mmo-template/issues) to discuss bugs or feature requests.

---

## Credits

Thanks to people who made this project possible:
- **Maps** designed by [@d-Cadrius](https://github.com/d-Cadrius).
- **Screenshots** provided by [@WithinAmnesia](https://github.com/WithinAmnesia).
- Thanks to [@Jackiefrost](https://github.com/Jackietkfrost) for their valuable contributions to the source code.
- Also thanks to [@Anokolisa](https://anokolisa.itch.io/dungeon-crawler-pixel-art-asset-pack) for allowing us to use its assets for this open source project!

## License
Source code under the [MIT License](https://github.com/SlayHorizon/godot-tiny-mmo/blob/main/LICENSE).
