> [!WARNING]  
> This project is still in experimental state.
# Godot Tiny MMO

A small-scale MMO / MMORPG developed with Godot Engine 4.3, without relying on the built-in multiplayer nodes.  

Both the client and server are included within the same project, utilizing export presets to manage the separation.  
These presets allow to export only the client-side without including server components, and vice versa.  

Feel free to explore the project details in the [**Wiki**](https://github.com/SlayHorizon/godot-tiny-mmo-demo/wiki).

![image](https://github.com/user-attachments/assets/ed1d527e-d05f-4f57-abd8-2d5af9227839)

## 🚀 Features

The current and planned features are listed below:

- [X] **Client-Server connection** through `WebSocketMultiplayerPeer`
- [x] **Playable on web browser**
- [X] **Authentication system** with Login UI
- [ ] **Create account**
- [ ] **Game version check**
- [X] **Entity synchronization** for players within the same instance
- [X] **Instance-based maps** with traveling between different map instances
- [x] **Basic RPG class system** with three initial classes: Knight, Rogue, Wizard
- [ ] **Private instances** for solo players or small groups
- [ ] **Weapons** at least one usable weapon per class
- [ ] **Basic combat system**
- [ ] **Entity interpolation** to handle rubber banding
- [x] **Three different maps:** Overworld, Dungeon Entrance, Dungeon
- [x] **Instance-based chat**
- [ ] **Database Server**
- [ ] **Authentication Server** (move the authentication system from game server)

*...and maybe more features later.*

You can track development and report issues by checking the [**open issues**](https://github.com/SlayHorizon/godot-tiny-mmo-template/issues) page.

## 🛠️ Getting Started

To get started with the project, follow these steps:
1. Clone this repository.
2. Open the project with **Godot 4.3**
3. In the Debug tab, choose **Customizable Run Instance...**
4. Enable **Multiple Instances** and set at least 2 or more.
5. Under **feature tags**, ensure to have:
   - Exactly **one** "server" tag
   - At least **one or more** "client" tags
6. (Optional) Add **--headless** under **Launch Arguments** for the server.
7. Run the project!

Example setup for multiple instances:  
![multiple-instances-screenshot](https://github.com/user-attachments/assets/5cf7cc61-e8e6-468d-b917-b505a59168cf)

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
