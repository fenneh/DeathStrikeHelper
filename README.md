# Death Strike Helper

A World of Warcraft addon that provides real-time feedback for Death Knight's Death Strike ability, helping you optimize your healing and timing.

## Features

- Visual feedback for Death Strike healing and overhealing amounts
- Timing indicator showing optimal usage moments
- Star rating system (1-5 stars) based on:
  - Healing efficiency (minimal overhealing)
  - Timing (based on Runic Power and health conditions)
- Customizable UI:
  - Adjustable text size and positions
  - Configurable colors and visibility
  - Movable frame with lock option
  - Toggle visibility of individual elements

## Death Strike Logic

The addon helps optimize Death Strike usage based on several factors:

### Timing Recommendations
- Shows a green plus (+) when it's optimal to use Death Strike:
  - When Runic Power is at or above 80
  - When health is below 50% and Runic Power is at least 40
- Shows a red minus (-) when:
  - Runic Power is above 110 (resource waste)
  - Conditions for optimal usage aren't met
- Shows a cooldown timer when Death Strike was recently used (5-second cooldown)

### Star Rating System

The star rating (1-5 stars) is calculated based on two main factors:

1. **Healing Efficiency** (Up to 2 bonus stars)
   - +2 stars: Over 80% healing efficiency (less than 20% overhealing)
   - +1 star: Over 60% healing efficiency (less than 40% overhealing)
   - +0 stars: Below 60% healing efficiency

2. **Timing** (Up to 2 bonus stars)
   - +2 stars: Used at optimal Runic Power (80+ RP) or during emergency (< 50% HP and 40+ RP)
   - +1 star: Used with adequate resources (40+ RP)
   - +0 stars: Used with poor timing (> 110 RP or low RP)

All ratings start at 1 star minimum and can gain up to 4 additional stars based on the above criteria.

The star color indicates the overall rating:
- 1 star: Red (Poor)
- 2 stars: Orange (Fair)
- 3 stars: Yellow (Good)
- 4 stars: Light Green (Very Good)
- 5 stars: Green (Excellent)

## Installation

1. Download the addon
2. Extract the folder into your `World of Warcraft\_retail_\Interface\AddOns` directory
3. Restart World of Warcraft if it's running
4. Enable the addon in your addon list

## Usage

The addon will automatically track your Death Strike usage and provide feedback:
- Green numbers show effective healing
- Red numbers show overhealing
- Plus/minus indicators show if the timing was optimal
- Star rating shows overall effectiveness

### Commands

- `/dsh` - Shows available commands
- `/dsh config` - Opens the configuration panel
- `/dsh test` - Shows test values to help with UI positioning
- `/dsh reset` - Resets the max healing seen value

### Configuration

Access the configuration panel through:
- `/dsh config` command
- Interface Options menu

You can customize:
- Icon and text sizes
- Text positions and visibility
- Frame size and appearance
- Font settings
- Background and border options

## Requirements

- World of Warcraft Retail
- Death Knight class

## Support

For issues or suggestions, please submit them through the project's issue tracker.

## License

This addon is released under the MIT License. 