Envision

Envision is a native Swift media client for macOS, iPhone, and iPad. It connects to a running Jellymax server and provides a native Apple-platform interface for browsing and playing media.

Overview

Envision acts as the client application for Jellymax. Rather than hosting or managing media itself, Envision connects to a Jellymax server over the network and uses the server to access media libraries, metadata, streams, and other server functionality.

┌─────────────────────┐
│      Envision        │
│                     │
│  macOS / iOS / iPadOS
└──────────┬──────────┘
           │
           │ HTTP / API
           ▼
┌─────────────────────┐
│      Jellymax        │
│       Server         │
└──────────┬──────────┘
           │
           ▼
      Media Library

Supported Platforms

Envision is designed for Apple platforms using Swift and SwiftUI.

* macOS
* iOS / iPhone
* iPadOS / iPad

Requirements

To use Envision, you need:

* A Mac, iPhone, or iPad running a supported OS version
* A running Jellymax server
* Network access to the Jellymax server
* The Jellymax server address and port

For example:

http://192.168.1.100:8097

or a remotely hosted server:

https://jellymax.example.com

Connecting to Jellymax

When Envision starts, enter the address of your Jellymax server.

Envision will attempt to establish a connection to the server before allowing you to access your media library.

The device running Envision must be able to reach the Jellymax server. For servers running on a local network, ensure that both devices are connected to the same network or otherwise have network connectivity between them.

Building

Requirements

* macOS
* Xcode
* Swift toolchain supported by the project

Clone the repository:

git clone https://github.com/thorjar/Envision.git
cd Envision

Open the Xcode project:

open Envision.xcodeproj

Select the desired target and destination in Xcode:

Envision
├── My Mac
├── iPhone
└── iPad

Then build and run the project using Xcode.

Project Structure

Envision/
├── Envision/                 # Main Envision application
├── EnvisionTV/               # tvOS-related client code
├── Envision.xcodeproj/       # Main Xcode project
├── EnvisionTV.xcodeproj/     # tvOS Xcode project
├── Configuration/            # Application configuration
├── Tests/                    # Tests
├── project-tv.yml            # tvOS project configuration
└── README-tvOS.md            # tvOS documentation

Technology

Envision is built primarily with:

* Swift
* SwiftUI
* AVFoundation / AVPlayer
* Native Apple networking and media APIs
* Xcode

The application is designed to provide a native Apple-platform experience rather than wrapping a web interface.

Jellymax

Envision requires a Jellymax server to provide the backend media services.

The Jellymax server is responsible for serving media and exposing the APIs used by Envision. Envision provides the native client interface used to interact with those services.

Development Status

Envision is under active development. Features, APIs, project structure, and platform support may change as development continues.

License

See the repository license for information about usage and distribution.