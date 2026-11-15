# SpTF-NASA-Hackathon-2026
Our team joined the NASA challenge Build a Junior Astronaut Mission Trainer, and this is the respective Github repository corresponding to the NASA Space Apps Challenge 2026.

## Mission flow

Choose a character, inspect life support and spacesuits in Room 1, then explore the outpost map. The Personal Building leads to the Exercise Room in Room 2; skipping exercise reduces movement speed. The Communications room in Room 3 contains the crew call.

Room 1 retrieves solar-flare events from NASA's [DONKI API](https://ccmc.gsfc.nasa.gov/DONKI-API/). Radiation is shown as high when an M- or X-class flare appears in the preceding seven days. Oxygen, carbon dioxide, and temperature are simulated readings. The public CCMC API does not require an API key. API/network errors are shown as unavailable, not as a fabricated radiation reading.
