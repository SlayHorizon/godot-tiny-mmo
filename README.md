> [!WARNING]  
> This project is in experimental state and gameplay features are missing (see [**#🚀 Features**](#-features)).  

# Godot Tiny MMO

A little web-based MMO / MMORPG demo developed with Godot Engine 4.x - 4.3,  
created without relying on the built-in multiplayer nodes.  

This project contains both client and server within the same codebase.  
Using custom export presets, you can easily [**Export Client and Server builds separately**](https://github.com/SlayHorizon/godot-tiny-mmo-demo/wiki/Exporting-the-project).  
This keeps exports safe and optimized by excluding unnecessary components.    

For additional details, check out the [**Wiki**](https://github.com/SlayHorizon/godot-tiny-mmo-demo/wiki).  

![project-demo-screenshot](https://github.com/user-attachments/assets/ca606976-fd9d-4a92-a679-1f65cb80513a)

## 🚀 Features

The current and planned features are listed below:

- [X] **Client-Server connection** through `WebSocketMultiplayerPeer`
- [x] **Playable on web browser and desktop**
- [x] **Network architecture** (see diagram below)
- [X] **Authentication system** through gateway server with Login UI
- [ ] **Account Creation** for permanent player accounts
- [x] **Guest Login** option for quick access
- [ ] **Game version check** to ensure client compatibility
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

Current network architecture diagram for this demo (subject to change):  
![architecture-diagram-26-10-2024](https://github.com/user-attachments/assets/78b1cce2-b070-4544-8ecd-59784743c7a0)


You can track development and report issues by checking the [**open issues**](https://github.com/SlayHorizon/godot-tiny-mmo-template/issues) page.

## 🛠️ Getting Started

To get started with the project, follow these steps:
1. Clone this repository.
2. Open the project in **Godot 4.3**.
3. In the Debug tab, select **Customizable Run Instance...**.
4. Enable **Multiple Instances** and set the count to **4 or more**.
5. Under **Feature Tags**, ensure you have:
   - Exactly **one** "gateway-server" tag.
   - Exactly **one** "master-server" tag.
   - Exactly **one** "game-server" tag.
   - At least **one or more** "client" tags
6. (Optional) Under **Launch Arguments**:
   - For servers, add **--headless** to prevent empty windows.
   - For any, add **--config=config_file_path.cfg** to use non-default config path. 
7. Run the project!

Setup example:  
![image](https://github.com/user-attachments/assets/abd2fd11-bb29-4d90-92c4-a8aefcdd7d52)  

## 🤝 Contributing

If you have ideas or improvements in mind, fork this repository and submit a pull request. You can also open an issue with the tag `enhancement`.

### To contribute:
1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a **Pull Request**

## Credits
- Maps designed by [@d-Cadrius](https://github.com/d-Cadrius).
- Screenshots provided by [@WithinAmnesia](https://github.com/WithinAmnesia).  
- Also thanks to [@Anokolisa](https://anokolisa.itch.io/dungeon-crawler-pixel-art-asset-pack) for allowing us to use its assets for this open source project!
