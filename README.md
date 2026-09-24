# Envision

Envision is a native Swift media client for **macOS, iPhone, and iPad**.
It connects to a running **Jellymax server** and provides a native
Apple-platform interface for browsing and playing media.

## Overview

Envision acts as the client application for Jellymax. Rather than
hosting or managing media itself, Envision connects to a Jellymax server
over the network to access media libraries, metadata, streams, and other
server functionality.

``` text
┌─────────────────────────┐
│         Envision         │
│                         │
│   macOS / iOS / iPadOS  │
└────────────┬────────────┘
             │
             │ HTTP / API
             ▼
┌─────────────────────────┐
│         Jellymax         │
│          Server          │
└────────────┬────────────┘
             │
             ▼
        Media Library
```

## Supported Platforms

Envision is designed for Apple platforms using Swift and SwiftUI.

-   macOS
-   iPhone
-   iPad

## Requirements

To use Envision, you need:

-   A Mac, iPhone, or iPad running a supported OS version
-   A running Jellymax server
-   Network access to the Jellymax server
-   The Jellymax server address and port

For example:

``` text
http://192.168.1.100:8097
```

or a remotely hosted server:

``` text
https://jellymax.example.com
```

## Connecting to Jellymax

When Envision starts, enter the address of your Jellymax server.

Envision will attempt to establish a connection to the server before
allowing access to the media library.

For servers running on a local network, ensure that the device running
Envision can reach the Jellymax server over the network.

## Building

### Requirements

-   macOS
-   Xcode
-   A Swift toolchain supported by the project

Clone the repository:

``` bash
git clone https://github.com/thorjar/Envision.git
cd Envision
```

Open the project in Xcode:

``` bash
open Envision.xcodeproj
```

Select the desired target and destination in Xcode and build the
application.

Supported destinations include:

-   My Mac
-   iPhone
-   iPad

## Project Structure

``` text
Envision/
├── Envision/                 # Main Envision application
├── EnvisionTV/               # tvOS client
├── Envision.xcodeproj/       # Main Xcode project
├── EnvisionTV.xcodeproj/     # tvOS Xcode project
├── Configuration/            # Application configuration
├── Tests/                    # Tests
├── project-tv.yml            # tvOS project configuration
└── README-tvOS.md            # tvOS documentation
```

## Technology

Envision is built primarily with:

-   Swift
-   SwiftUI
-   AVFoundation / AVPlayer
-   Native Apple networking and media APIs
-   Xcode

The application is designed to provide a native Apple-platform
experience rather than wrapping a web interface.

## Jellymax

Envision requires a Jellymax server to provide its backend media
services.

Jellymax is responsible for serving media and exposing the APIs used by
Envision. Envision provides the native client interface for interacting
with those services.

## Development Status

Envision is under active development. Features, APIs, project structure,
and platform support may change as development continues.

## License

See the repository license for information about usage and distribution.
