# Options for DVD/CD/Blu-Ray Drive Passthrough from Linux Proxmox Host to Virtual Machine:
_NOTE: It was determined to just use the Proxmox host of the NAS machine to burn disks and use the Linux CLI burning disks_
- The information regarding IOMMU and DVD RW+ is optional
- Ideally a SATA-to-USB converter could be purchased/used to passthrough just the DVD play/burner to a VM on the host, but not necessary when the host can just be used on the NAS machine instead (with minimal overhead)
- Basically it was discovered that the entire SATA controller would have to be passed through, but this would cause resources (such as the boot drive for Proxmox) to also be passed through to the VM and obviously cause Proxmox host boot failure/issues.
USB Passthrough (Recommended and Easiest for a USB-connected DVD Drive):

This is the simplest way to dedicate a USB device (like your SATA-to-USB connected DVD drive) to a VM.

Steps:

Plug in the USB DVD drive to your Proxmox host.

Go to your VM's settings in the Proxmox web interface.

Navigate to the Hardware tab.

Click Add -> USB Device.

Select "Use USB Vendor/Device ID".

From the dropdown list, choose your USB DVD drive (it will show its Vendor ID:Product ID and usually a description).

Click Add.

Start or restart the VM.

Why this is best: It's straightforward, doesn't require complex command-line edits on the host, and generally provides the VM with full, direct access to the USB device, which is usually sufficient for burning.

# Enable IOMMU for hardware passthrough in Proxmox (e.g. DVD for burning files/mp3s, GPUs etc.)
- Make sure IOMMU (Input-Output Memory Management Unit) is enabled for Proxmox kernel boot
```
cat /proc/cmdline
# You should see something like 'intel_iommu=on'
```
- If you do not see intel_iommu=on when checking the kernal command line (above), you will need to figuer out if grub or systemd-boot is used as the bootloader
```
# Determine the bootloader:
proxmox-boot-tool status
# Look at the "Bootloader" line in the output. It will tell you if it's "grub" or "systemd-boot".
# Edit grup config: 
nano /etc/default/grub
# Look for GRUB_CMDLINE_LINUX_DEFAULT="quiet" and add intel_iommu=on like this:
# optionally iommu=pt for some improved performance with GPUs and other high IO devices
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
# Close/Save the file and run 
update-grub
```
- Add VFIO modules (if you haven't already)

- It's good practice to ensure the necessary kernel modules for PCI passthrough are loaded at boot.
```
nano /etc/modules
# Add the following lines to the end of the file:
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
# Save and exit: (Ctrl+X, then Y, then Enter)
# Update the initramfs: This ensures the modules are included in the early boot process.
update-initramfs -u -k all
# Then reboot:
reboot
```
- After reboot, check the kernel command line again to make sure IOMMU is enabled after reboot
```
cat /proc/cmdline
# You should see something like 'intel_iommu=on' and iommu=pt (if enabled)
```
- Check IOMMU status in dmesg:
```
dmesg | grep -e DMAR -e IOMMU
# You should still see messages like DMAR: IOMMU enabled and DMAR: Using Queued invalidation (or similar for AMD).
# And check IOMMU groups again and you should still see the IOMMU groups:
for d in /sys/kernel/iommu_groups/*/devices/*; do n=${d#*/iommu_groups/*}; n=${n%%/*}; printf 'IOMMU group %s ' "$n"; lspci -nns "${d##*/}"; done
```

# Add DVD RW+ for passthrough device to VM hosting Docker
- Add the DVD drive identifier to the VM config for passthrough
```
# SSH To the Proxmox host and enter:
ls -l /dev/disk/by-id/ | grep sr

# This should give you something like: 
ata-HL-DT-ST_DVD+_-RW_GU90N_KL1G9MC0650 -> ../../sr1
# This is a stable identifier that won't shift like /dev/srX might
```
- Edit the VM config manually:
```
nano /etc/pve/qemu-server/<VMID>.conf
```
- Replace the existing sata0: or ide2: line with:
```
sata0: /dev/disk/by-id/ata-HL-DT-ST_DVD+_-RW_GU90N_KL1G9MC0650,media=cdrom
# Or optionally use scsi0 if you prefer SCSI passthrough
# Save and start the VM
```

# USB - SATA-to-USB (External Drive) Passthrough option _Recommended_
If your CD/DVD drive is an external USB drive, or you can connect an internal SATA drive via a cheap SATA-to-USB adapter, this is often the simplest and most reliable method for full functionality.

In the Proxmox VM's Hardware settings, click "Add" -> "USB Device".

Select your USB CD/DVD drive from the list.

Crucial Note: This dedicates the USB device to the VM. The Proxmox host will no longer have direct access to it.

Prerequisites:

- Your CD/DVD drive is an external USB drive.
- (If internal SATA) You have a reliable SATA-to-USB adapter, and you can connect the internal drive to a USB port on your Proxmox host.

Steps:

Identify the USB Device on Proxmox Host:

- Plug in your USB DVD drive to your Proxmox host.

- Open the Proxmox Shell (Datacenter -> Your Node -> Shell).

- Run lsusb. Look for your DVD drive in the output. It will show you its Vendor ID and Product ID (e.g., Bus 00X Device 00Y: ID abcd:1234 VendorName ProductDescription). Note down the abcd:1234 part.

- If you're unsure which one it is, unplug it, run lsusb, note the difference, then plug it back in and run lsusb again.

Add USB Device to your VM via Proxmox Web GUI:

- Go to your VM in the Proxmox web interface.

- Navigate to the Hardware tab.

- Click Add -> USB Device.

- In the "Add: USB Device" window:

	- Choose "Use USB Vendor/Device ID".

	- Select your CD/DVD drive from the dropdown list (it should show the abcd:1234 ID and description).

	- Click Add.

Start/Restart the VM:

- Start or restart your VM.

- Inside the VM, the DVD drive should now appear as a native USB device.

Access in Docker (inside the VM):

- Once the DVD drive is recognized by the VM's operating system, ensure your Docker container has the necessary privileges and device mappings.

- When you run your Docker container, you'll need to map the device:

```
docker run -it --rm --privileged -v /dev/sr0:/dev/sr0 your_burning_image /bin/bash
```
- Replace /dev/sr0 with the actual device path in your VM (check with lsblk or lsscsi inside the VM).

- --privileged is often needed for burning software, as it requires low-level access. You might be able to get away with more granular --device=/dev/sr0 and specific capabilities if you know them.

- your_burning_image is your Docker image containing the burning software (e.g., k3nz0/dvdauthor or an image you've built with brasero, k3b, wodim, etc.).

# Alternatively - Setup CD/DVD Burning Tools on NAS Proxmox Host:
_Note: no adapter is needed with this option, but will add bloat/packages to the Proxmox host._
Use the Proxmox host directly to burn disks. This is often the simplest solution when PCI passthrough isn't feasible for an internal SATA drive and you don't have a USB adapter.

Here's the general process:

Identify the DVD Drive on the Proxmox Host:

Log into your Proxmox host via SSH or the Shell in the web GUI.

Run lsblk to list block devices. Your DVD drive will likely appear as /dev/sr0 (or sometimes /dev/sr1, etc.).

You can also use lsscsi to get more details about the SCSI devices, which will usually list your DVD burner with its model name.

Install Burning Software on the Proxmox Host:

Proxmox is based on Debian, so you can use Debian's package manager (apt) to install burning utilities.

First, ensure your package lists are up to date:

```
apt update
```
Then, install burning tools. Common command-line tools for burning are wodim (for CD/DVD writing) and genisoimage (for creating ISO images). dvd+rw-tools is also useful.

```
apt install wodim genisoimage dvd+rw-tools
```
If you prefer a more user-friendly graphical interface (though this is a server, so a GUI might be overkill and add bloat): You would need to install a desktop environment and a GUI burning application like k3b or brasero. This is generally not recommended on a Proxmox host, as it adds unnecessary dependencies and overhead to your hypervisor. Stick to the command-line tools for a cleaner, more stable system.

Prepare the Data to Burn:

Ensure the files you want to burn are accessible on the Proxmox host's filesystem. You might copy them from a share, download them, etc.

Create an ISO Image (if burning data):

If you're burning a data DVD/CD, it's best practice to create an ISO image first. This ensures the filesystem structure is correct and makes the burning process more robust.

Navigate to the directory containing the files/folders you want to burn.

Use genisoimage (or mkisofs, which genisoimage is often a symlink to):

```
genisoimage -o /path/to/my_disc.iso -R -J -V "Disc Label Here" /path/to/source_data/
```
Replace /path/to/my_disc.iso with the desired output path and filename for your ISO.

Replace /path/to/source_data/ with the directory containing the files you want to burn.

-R: Rock Ridge extensions (for long filenames, UNIX permissions, etc.)

-J: Joliet extensions (for compatibility with Windows long filenames)

You might also add -V "DISC_LABEL" to set a volume label.

*Recommendation:* After creating the ISO, always check its size using ls -lh /path/to/your.iso and compare it to the capacity of your blank disc (e.g., ~700M for CD, ~4.7G for single-layer DVD, ~8.5G for dual-layer DVD).

Burn the Disc:

Important: Make sure no VMs are trying to access the drive, and that you unmounted any discs that might be in it (e.g., umount /dev/sr0).

Erase Rewritable Discs (if applicable):

```
wodim dev=/dev/sr0 blank=fast # for CD-RW
dvd+rw-format /dev/sr0       # for DVD-RW (formats to sequential mode)
```
Burn the ISO image:

```
wodim dev=/dev/sr0 -v -data /path/to/my_disc.iso
```
dev=/dev/sr0: Specifies your DVD burner device. Double-check this path!

-v: Verbose output.

-data: Indicates you're burning data.

/path/to/my_disc.iso: The path to the ISO image you created.

For burning an actual audio CD: The process is slightly different and involves preparing audio tracks in a specific format (.wav files) and using wodim with audio-specific options. This is less common on a server.

Considerations and Best Practices:

Proxmox Host Stability: While it's technically possible, generally, it's best practice to keep your Proxmox host as lean and dedicated to virtualization as possible. Installing extra software like burning tools adds more packages, dependencies, and potential points of failure or resource contention. However, for a one-off or infrequent task, it's perfectly acceptable.

## Create an Audio CD
For Audio CDs:

The files must be in a specific format: WAV files, 44.1 kHz sample rate, 16-bit depth, stereo. If your WAV files don't meet these specifications, you'll need to convert them first (tools like sox or ffmpeg can do this). wodim (or cdrskin / xorrecord) will often give an "Inappropriate audio coding" error if the WAVs are not correct.

_You do not create an ISO image first. You burn the WAV files directly._

The burning tool handles the CD-DA specific formatting.

The order of the files in the command line (or a list file) dictates the track order on the CD.

You'll typically use wodim (or cdrskin / xorrecord if you prefer the xorriso suite).

Here's the general command using wodim:

1. Find your CD/DVD burner device:

First, you need to identify the device name of your optical drive.

```
wodim --devices
```
This will output something like:
```
wodim: Overview of accessible drives (1 found) :
-------------------------------------------------------------------------
 0  dev='/dev/sr0'   rwrw-- : 'VENDOR' 'MODEL'
-------------------------------------------------------------------------
```
Note the dev= path (e.g., /dev/sr0, or /dev/cdrom, or ATA:1,0,0 for older systems). Use the most modern /dev/srX or /dev/cdrom if available.

2. Burn the WAV files to an Audio CD:

Replace /dev/sr0 with your actual device and /path/to/your/wav_files/*.wav with the actual path to your WAV files.

```
wodim dev=/dev/sr0 -v -dao -audio -pad /path/to/your/wav_files/*.wav
```
Here's a break down of the options:

`wodim`: The command-line utility for burning CDs/DVDs.

`dev=/dev/sr0`: Specifies your CD/DVD burner device. Crucial: Replace /dev/sr0 with the actual device path you found from wodim --devices.

`-v`: Verbose output, shows progress.

`-dao`: Disc At Once mode. This is generally preferred for audio CDs as it writes the entire disc in one continuous session without leaving gaps between tracks, which helps with playback compatibility.

`-audio`: Tells wodim that the following files are audio tracks (WAV format, 44.1kHz, 16-bit, stereo).

`-pad`: Pads the audio data to ensure proper data length for each track, essential for CD-DA.

`/path/to/your/wav_files/*.wav`: This is where you specify your WAV files.

If they are all in one directory and you want to burn them alphabetically/numerically, *.wav (or 01_song.wav 02_song.wav ...) works.

Crucially for order: The order you list the files on the command line is the order they will be burned to the CD. If you want a specific order that isn't alphabetical, you must list them explicitly:

```
wodim dev=/dev/sr0 -v -dao -audio -pad "/path/to/wavs/03 Baa Baa Black Sheep.wav" "/path/to/wavs/01 Twinkle Twinkle.wav" "/path/to/wavs/02 Old MacDonald.wav"
```
(Note the quotes for filenames with spaces).

Important Considerations:

- WAV File Format: As mentioned, ensure your WAV files are:
    - 44.1 kHz Sample Rate
    - 16-bit Sample Depth
    - Stereo
    - Uncompressed PCM format

    If not, you'll get errors. sox is a great tool for conversion:
    ```
    #(converts to stereo, 44.1kHz, 16-bit)
    sox input.wav -c 2 -r 44100 -b 16 output.wav 
    ```

- Disc Space: Audio CDs have a fixed capacity, typically around 74-80 minutes of audio. Ensure your total WAV duration doesn't exceed this. wodim will warn you if it's too large.

- Blank CD-R: Make sure you use a blank CD-R (not CD-RW if you want maximum compatibility with older players, though CD-RWs will work too).

- Unmount Drive: Make sure the CD burner device is not mounted before you start the burn.

- Burning Speed: You can add speed=X (e.g., speed=8) if you want to explicitly set the burn speed. Slower speeds sometimes lead to more reliable burns.

- This command specifically creates a standard Audio CD that should play in any regular CD player.

Install SoX on Proxmox:

```
sudo apt update
sudo apt install sox libsox-fmt-all # libsox-fmt-all gets you support for MP3, FLAC, etc.
```
Convert all MP3 files in a directory to WAV files, specifically for burning an Audio CD. This means ensuring the WAVs are 44.1 kHz, 16-bit, stereo, uncompressed PCM.

_It's highly recommended to keep your original MP3s in one directory and convert them into a separate directory. This prevents clutter and accidentally overwriting original files._

Paste the following command (after changing directory variables) into Proxmox shell:

_Make sure to create the `WAV_DIR` directory for wav files after conversion, if it doesn't already exist._
```
# 1. Define your input and output directories
MP3_DIR="/opt/disc-burn/benolijamz"    # Replace with the actual path to your MP3 folder
WAV_DIR="/opt/disc-burn/benolijamzwav" # Replace with the desired path for WAV output

# 2. Create the output directory if it doesn't exist
mkdir -p "$WAV_DIR"

# 3. Navigate to the MP3 directory
cd "$MP3_DIR" || { echo "Error: MP3 directory not found or accessible."; exit 1; }

# 4. Loop through each MP3 file and convert it
for mp3_file in *.mp3; do
    # Skip if no mp3 files are found (e.g., if the glob matches literal "*.mp3")
    if [ ! -f "$mp3_file" ]; then
        echo "No MP3 files found in '$MP3_DIR'."
        break
    fi

    # Construct the output WAV filename
    wav_file="${WAV_DIR}/${mp3_file%.mp3}.wav"

    echo "Converting '$mp3_file' to '$wav_file'..."

    # SoX command for CD-Audio WAV format:
    # -c 2: Force 2 channels (stereo)
    # -r 44100: Force 44.1 kHz sample rate
    # -b 16: Force 16-bit sample depth (signed integer PCM)
    sox "$mp3_file" -c 2 -r 44100 -b 16 "$wav_file" norm -0.5

    # Check if the conversion was successful
    if [ $? -eq 0 ]; then
        echo "Successfully converted '$mp3_file'."
    else
        echo "ERROR converting '$mp3_file'. Check SoX output above."
    fi
done

echo "Conversion process complete."
```
How to use the script:

Copy and paste the entire block of code into your Proxmox shell.

EDIT THE MP3_DIR and WAV_DIR variables at the beginning of the script to your actual paths.

Press Enter to run it.

Explanation of the sox command within the loop:

`sox "$mp3_file"`: The input MP3 file. Quotes are important for filenames with spaces.

`-c 2`: Sets the number of audio channels to 2 (stereo). This is required for Audio CDs.

`-r 44100`: Sets the sample rate to 44,100 Hz. This is the standard for Audio CDs.

`-b 16`: Sets the bit depth to 16 bits. This is the standard for Audio CDs.

`"$wav_file"`: The output WAV file name. Again, quotes are important.

The `norm` effect in SoX automatically adjusts the volume so that the loudest peak in the audio reaches a specified decibel level (relative to full scale). Using a value slightly below 0 dB (like -0.1 dB or -0.5 dB) provides a small "headroom" to prevent clipping during conversion.

`norm -0.5`: This tells SoX to normalize the audio so that its peak amplitude reaches -0.5 dB (decibels) relative to the maximum possible level. This leaves a tiny bit of space (headroom) and usually prevents clipping warnings. You can try norm -0.1 or norm -1.0 if you want more or less headroom.

This will give you a new folder filled with WAV files, all correctly formatted for burning onto a standard Audio CD.

If needed, erase the wav directory to start over (example, adjust the `norm` command to eradicate clipping warnings from SoX:
```
# First list contents to be deleted:
ls -l /opt/disc-burn/benolijamzwav/

# Delete contents (WARNING - this actually removes everything without warning):
rm -rf /opt/disc-burn/benolijamzwav/*
```

Here's the command to check your wav folder's contents to determine if they'll fit on a CD:

```
du -sh /opt/disc-burn/benolijamzwav
```
Here's a break down of the options:

`du`: This is the core "disk usage" command.

`-s`: This stands for "summarize." It tells du to display only a total for the specified directory, rather than listing the size of every subdirectory and file within it individually.

`-h`: This stands for "human-readable." It displays the sizes in a format that's easy for humans to read (e.g., K for kilobytes, M for megabytes, G for gigabytes) instead of just bytes or 512-byte blocks.

`/opt/disc-burn/benolijamzwav`: This is the full path to the directory you want to check the size of.

Example Output:
```
450M    /opt/disc-burn/benolijamzwav
```
This output would tell you that the benolijamzwav directory and all its contents combined are taking up 450 Megabytes of space.

CD Capacity for Reference:

A standard CD-R typically holds 700 MB (megabytes) of data.

Some older or less common CD-Rs might hold 650 MB.

An Audio CD (CD-DA) has a maximum duration, typically 74 to 80 minutes. The amount of data for 80 minutes of CD-quality audio (44.1 kHz, 16-bit, stereo) is roughly 700 MB.

So, if your `du -sh` command shows a size like `450M`, it means the data should comfortably fit on a standard 700MB CD. If it's, for example, `800M` or` 1.2G`, it won't fit on a single CD, and you'd need to either split it across multiple CDs or use a different media type (like a DVD).

## Step-by-step guide to read and copy data files (like documents, images, software installers) and MP3s from a CD/DVD on your Proxmox host's command line:

Part 1: Prerequisites (If you haven't already)
Ensure the DVD drive is detected by the host:

Log into your Proxmox host via SSH or the Shell in the web interface.

Run:

```
lsblk
```
Look for an entry like /dev/sr0 (it might be sr1, sr2, etc., if you have multiple optical drives or other SCSI devices). This is your CD/DVD drive.

If you previously blacklisted the SATA controller's driver to pass it to a VM, make sure you've reversed that blacklisting and rebooted your Proxmox host. Otherwise, the host won't be able to see or use the drive.

Install necessary tools:

```
apt update
apt install p7zip-full # For extracting ISOs or other compressed archives if needed
```
p7zip-full is good for various archive formats you might find on data discs.

Part 2: Reading and Copying Data CDs/DVDs (Files, documents, software)
This is the most common use case.

Insert the CD/DVD into the drive.

Create a mount point:
You need a directory where the contents of the CD/DVD will be made accessible.

```
mkdir /mnt/cdrom
```
(You can choose any directory, but /mnt/cdrom or /media/cdrom are conventional.)

Mount the CD/DVD:
Use the mount command to attach the CD/DVD to your created mount point.

```
mount /dev/sr0 /mnt/cdrom
```
Replace /dev/sr0 with the correct device name for your DVD drive if it's different.

If you get an error about "wrong fs type, bad option, bad superblock...", it might be a disc with an unusual filesystem, or corrupted. Try adding -t iso9660 for older CD/DVDs:

```
mount -t iso9660 /dev/sr0 /mnt/cdrom
```
For DVDs, sometimes specifying -t udf helps if iso9660 fails, though modern Linux kernels often auto-detect:

```
mount -t udf /dev/sr0 /mnt/cdrom
```
Permissions error: If you get a "Permission denied" error, ensure you are running as root (which you usually are in the Proxmox shell, or use sudo).

Verify the contents:
After mounting, you can list the contents of the disc:

```
ls -l /mnt/cdrom
```
You should see the files and directories from your CD/DVD.

Copy the contents:
Use the cp command to copy files or directories.

To copy all files and folders (including hidden ones) from the disc to a destination:

```
cp -Rv /mnt/cdrom/* /path/to/your/destination/
cp -Rv /mnt/cdrom/.[!.]* /path/to/your/destination/ # To also copy hidden files/folders
```
Or, a more robust way to copy everything, including hidden files/directories:

```
rsync -av --progress /mnt/cdrom/ /path/to/your/destination/
```
rsync is generally preferred for copying directories as it handles permissions, timestamps, and can resume if interrupted.

Replace /path/to/your/destination/ with the actual path where you want to save the files (e.g., /var/lib/vz/template/iso/my_disk_content/ or a network share).

Unmount the CD/DVD:
Once you've finished copying, it's crucial to unmount the disc before ejecting it.

```
umount /mnt/cdrom
```
If umount says "target is busy", it means some process is still accessing the mount point. Navigate out of /mnt/cdrom (e.g., cd ~), close any programs that might be using it, and try again. You can use lsof | grep /mnt/cdrom to find processes holding it open.

Eject the CD/DVD:

```
eject /dev/sr0
```
Part 3: Ripping Audio CDs (MP3s)
Ripping audio CDs requires specialized software as they are not standard filesystems but rather audio tracks.

Use cd-info to view audio disc info:
```
apt update
# Install cd-info tools if not already installed:
apt install libcdio-utils

# View audio disc info:
cd-info --no-device-info /dev/sr0
```

Install audio ripping tools:
The abcde (A Better CD Encoder) tool is excellent for command-line ripping and can automatically convert to MP3. You'll also need lame for MP3 encoding and cdparanoia for audio extraction.

```
apt install abcde lame cdparanoia
```
abcde often automatically pulls in cdparanoia.

Insert the Audio CD into the drive.

Configure abcde (optional but recommended for custom output):
abcde is highly configurable. You can create a personal config file to define output format, directory structure, etc.

```
cp /etc/abcde.conf ~/.abcde.conf
nano ~/.abcde.conf
```
Look for and uncomment/modify these lines:

OUTPUTDIR="$HOME/Music" (or specify a different path like /var/lib/vz/template/iso/my_mp3s/)

OUTPUTFORMAT='${ARTISTFILE}/${ALBUMFILE}/${TRACKNUM}. ${TRACKFILE}' (defines naming)

ACTIONS=cddb,playlist,getalbumart,tag,move,clean (default actions)

CDTEXTFILE=~/.cdtext

MP3ENCODERR="lame -V2 --vbr-new -q0" (adjust -V2 for VBR quality; lower number is higher quality, e.g., -V0 for best).

PADTRACKS=y (pads track numbers with leading zeros)

EXT=mp3 (ensures output is .mp3)

MAXPROCS=2 (use multiple cores for encoding)

Start the ripping process:
Navigate to your desired output directory (or ensure OUTPUTDIR is set in your config).

```
cd /path/to/your/destination/for_mp3s
abcde
```
abcde will prompt you to identify the CD from online databases (CDDB). Choose the correct entry or press q to quit and manually edit if needed.

It will then extract the audio tracks, encode them to MP3, and place them in the specified directory structure (e.g., Artist/Album/01. Song Title.mp3).

This process can take some time depending on the CD length and your CPU speed.

Verify the MP3s:
Check the directory you specified in OUTPUTDIR.

Eject the CD:

```
eject /dev/sr0
```
You now have the data files or MP3s copied from your CD/DVD to your Proxmox host's storage.


# Addendum - Controlling sort order for files in ISO prior to burning:
The order of files on a burned disc is primarily determined by how the ISO image is created using genisoimage (or mkisofs).

genisoimage (and its alternatives like xorrisofs) typically processes files in a "depth-first traversal" of the directory tree, and the exact order can sometimes be influenced by the underlying filesystem's inode order, not necessarily alphabetical order as ls might show.

Here are the main strategies to control the burning order:

1. Renaming Files/Folders with Prefixes (Simplest for Data Discs)
This is the most straightforward and universally effective method for data CDs/DVDs (including MP3 data discs).

How it works: Files and folders are generally written to the ISO image (and thus the disc) in alphanumeric order. By adding numerical prefixes to your filenames and directory names, you can force a specific order.

Example:
Let's say you have these MP3s:

My Favorite Song.mp3

Another Great Track.mp3

The Best One.mp3

Rename them to:

01_The Best One.mp3

02_Another Great Track.mp3

03_My Favorite Song.mp3

When you create the ISO from a directory containing these, genisoimage will process them in the order 01_..., 02_..., 03_....

For folders: The same applies. If you have subfolders, prefix them:

01_Intro

02_Main_Content

03_Outro

Benefit: This method is simple, requires no special genisoimage options, and is very reliable.

2. Using a sort File with genisoimage (More Advanced)
*NOTE: specifying a sort file for genisoimage does not work if the files are already appended with a number.*
genisoimage has a powerful -sort option that allows you to provide a text file specifying the exact order of files and directories within the ISO image. This gives you granular control.

How it works:

Create a text file (e.g., sort_order.txt) where each line specifies a path to a file or directory that should be included, in the desired order.

Use the -sort option with genisoimage pointing to this file.

genisoimage will use this file as its guide for ordering.

Steps:

a.  Prepare your source directory: Let's say all your files are in /home/user/my_disc_content/.

b.  Create the sort_order.txt file:
Open a text editor: nano sort_order.txt

  Inside this file, list the files and directories relative to your source folder, one per line, in the *exact order* you want them to appear on the disc.

  **Example `sort_order.txt`:**
  ```
  /first_track.mp3
  /folder_a/intro.txt
  /folder_a/song_1.mp3
  /folder_a/song_2.mp3
  /folder_b/final_notes.txt
  /cover_art.jpg
  ```
  * **Important:** Paths must be absolute from the *root of the ISO image*, which corresponds to the base directory you give to `genisoimage`. If your MP3s are directly in `/home/user/my_disc_content/`, then `/first_track.mp3` refers to `/home/user/my_disc_content/first_track.mp3`.
  * **Note:** when using the -sort option with genisoimage, the sort file will work correctly even if filenames contain spaces, as long as each filename is on a separate line.
  To copy a playlist's sort order from iTunes (on Windows with Excel installed):
	* select the playlist in the sidebar, then go to File > Library > Export Playlist
	* Change the file type from txt to csv after saving the playlist.txt file exported from iTunes
	* Open the file in Excel, open the VBA editor (ALT+F11)
	* Insert a new module In the VBA editor, in the "Project Explorer" pane on the left, right-click on your workbook name (e.g., VBAProject (your_workbook_name.xlsx)).
	* Go to Insert > Module.
	* Paste the VBA Code:
```
' Excel Function to extract filename from a full path and format for genisoimage sort file
'
' Arguments:
'   fullPath (String): The complete file path (e.g., "C:\Users\username\Music\file.mp3")
'
' Returns:
'   String: The filename prefixed with a forward slash (e.g., "/file.mp3")
'           Returns "/" if the input path is empty or invalid.
'
Function GetGenisoimageSortFileName(fullPath As String) As String

    Dim lastBackslashPos As Long
    Dim fileNameOnly As String

    ' Check if the input path is empty or not a string
    If Not IsEmpty(fullPath) And IsString(fullPath) Then
        ' Find the position of the last backslash
        lastBackslashPos = InStrRev(fullPath, "\")

        ' If a backslash is found, extract the part after it
        If lastBackslashPos > 0 Then
            fileNameOnly = Mid(fullPath, lastBackslashPos + 1)
        Else
            ' If no backslash, the entire path is the filename
            fileNameOnly = fullPath
        End If

        ' Prepend a forward slash and return the result
        GetGenisoimageSortFileName = "/" & fileNameOnly
    Else
        ' Handle empty or invalid input
        GetGenisoimageSortFileName = "/" ' Or "" if you prefer an empty string for invalid input
    End If

End Function

' Helper function to check if a variable is a string
Private Function IsString(ByVal v As Variant) As Boolean
    If VarType(v) = vbString Then
        IsString = True
    ElseIf VarType(v) = vbVariant And TypeName(v) = "String" Then ' For some specific cases where VarType might be vbVariant
        IsString = True
    Else
        IsString = False
    End If
End Function
```
  * Close the VBA Editor (either press the "X" or hit Alt+F11 again)
  * Use the function in your Excel Worksheet
  * For example, copy the full path column from the exported playlist into a new worksheet column A, then in cell B2 (or B1 if no header was copied) enter the following:
  * '=GetGenisoimageSortFileName(A1)' > Press Enter and drag the formula down to aply it to the full list
  * Copy the sort file names to a plain txt file and use this in your ISO command like below/next-step (c.).
  * **Note:** Make sure to use Linux Line endings in the txt file used for sorting.  You can do this via NotePad++ > Edit > EOL Conversion > Unix (LF)
  * Note: make sure to copy all the songs (mp3 files) to a directory on the server or container where genisoimage is installed.

c.  Generate the ISO using the -sort option:
```
genisoimage -o /path/to/ordered_disc.iso -R -J -l -V "ORDERED_MUSIC" -sort sort_order.txt /home/user/my_disc_content/ 
```
* /home/user/my_disc_content/ is your base source directory.
* sort_order.txt should be in the directory where you run the genisoimage command, or you can provide its full path.

Benefits: Offers precise control over file order.

Drawbacks: Requires manual creation/management of the sort_order.txt file, which can be tedious for many files.

3. For Audio CDs (Red Book Audio)
When burning an actual audio CD (-audio option with wodim):

wodim burns the .wav files (or other audio formats it supports for direct burning) in the order you specify them on the command line.

Example:

```
wodim dev=/dev/sr0 -v -audio /path/to/wavs/01_Intro.wav /path/to/wavs/02_Song.wav /path/to/wavs/03_Outro.wav
```
Best Practice:

Convert your MP3s to WAVs (using ffmpeg or sox).

Rename the WAV files with numerical prefixes (e.g., 01_TrackName.wav, 02_AnotherTrack.wav).

Then, use a wildcard or list them in order: wodim dev=/dev/sr0 -v -audio *.wav (if in the correct directory and named numerically).

Choose the method that best suits the type of disc you're burning and the level of control you need. For data discs with MP3s, simply renaming files with 01_, 02_, etc., is usually the easiest and most effective way to ensure a specific playback order.

See [burn_audio_cd.sh](https://github.com/Three50seven/benoli-homelab/blob/main/servers/benolinas/scripts/burn_audio_cd/burn_audio_cd.sh) script for a more automated approach to burning MP3 files to an Audio disc format.

_Before running script, make sure the following pre-requisites are met:_
```
**Before you run this script:**

1.  **Install Required Tools:**
    ```bash
    sudo apt update
    sudo apt install sox libsox-fmt-mp3 python3-mutagen wodim bc # 'bc' is for floating point math
    ```
    * `sox`: For audio conversion and concatenation.
    * `libsox-fmt-mp3`: SoX plugin for MP3 support.
    * `python3-mutagen`: Provides `mid3v2` for reading MP3 tags.
    * `wodim`: The CD burning utility.
    * `bc`: For precise floating-point arithmetic needed for CUE sheet timings.

2.  **Edit Configuration Variables:**
    * **`MP3_SOURCE_DIR`**: **Crucially, set this to the full path of the directory containing your MP3 files.**
    * **`OUTPUT_DIR`**: Choose a working directory where the temporary WAVs, the master WAV, and the CUE sheet will be created. `/opt/disc-burn/audio_cd_project` is a good default, but ensure it exists or can be created.
    * **`CD_BURNER_DEVICE`**: **Find your actual CD/DVD burner device path** by running `sudo wodim --devices` and replacing `/dev/sr0` with the correct path (e.g., `/dev/sr1`, `/dev/cdrom`, etc.).

3.  **Permissions:**
    * Ensure the user running the script has read access to `MP3_SOURCE_DIR` and write access to `OUTPUT_DIR`.
    * The `wodim` command requires `sudo` (root privileges) to access the CD burner device.

4.  **MP3 Tagging Quality:**
    * The quality of the CD-Text (Artist, Title, Album) on your burned CD will depend entirely on the accuracy and completeness of the ID3 tags in your original MP3 files.
    * If tags are missing or incorrect, the CUE sheet will use "Unknown Artist" or "Untitled Track".

**How to use the script:**

1.  **Save:** Copy the entire code block above and paste it into a file, e.g., `burn_audio_cd.sh`.
2.  **Make Executable:** `chmod +x burn_audio_cd.sh`
3.  **Run:** `./burn_audio_cd.sh`
4.  **Follow Prompts:** The script will pause and ask you to insert a blank CD-R before burning.

This script automates the complex parts, allowing you to burn professional-looking Audio CDs with CD-Text directly from your MP3 collection on your Proxmox host.
```

## Checking ISO File Sort Order:
The best way to check the file order within an ISO image (especially one created with the sort option) is to mount the ISO file as a loopback device on your Proxmox host and then browse its contents.

Here's how to do it:

Step 1: Create a Mount Point for the ISO
```
mkdir /mnt/iso_test
```
(You can choose any convenient directory for this purpose.)

Step 2: Mount the ISO File as a Loopback Device
This command will treat your ISO file as if it were a physical disc and mount its filesystem.

```
mount -o loop /path/to/your_iso_file.iso /mnt/iso_test
```
Replace /path/to/your_iso_file.iso with the actual path and name of the ISO file you created (e.g., /path/to/ordered_disc.iso).

/mnt/iso_test is the mount point you just created.

Step 3: Browse the Mounted ISO Contents and Check Order
Now, you can navigate into the mounted ISO and list its contents. The key is to use commands that will show you the directory entries in their actual disk order rather than just alphabetically (which ls often does by default).

List contents (default ls):

```
ls -l /mnt/iso_test/
```
This will show you the files. However, keep in mind that ls on many Linux distributions (including Debian/Proxmox) by default sorts alphabetically. So, if you used numerical prefixes, ls will show them in that order, which is a good initial confirmation.

Using ls with -f (unsorted):
This is the most reliable way to see the actual directory entry order as stored on the filesystem (which is what genisoimage would have written).

```
ls -f /mnt/iso_test/
```
Explanation of -f: The -f option for ls disables sorting. It lists entries in directory order. If you used the -sort option with genisoimage, this command should reflect that precise order. If you used numerical prefixes, and genisoimage processed them in that numerical order, then ls -f will also show that.

Recursive listing (if you have subdirectories):

```
ls -lfR /mnt/iso_test/
```
This will list all files and subdirectories recursively, disabling sorting at each level, giving you the raw order.

Using isoinfo (for deep ISO9660 inspection):
The isoinfo utility (part of the genisoimage or cdrtools package) can directly inspect the ISO9660 filesystem structure. This is a very technical way to look at it, but it gives you detailed information about file locations.

```
isoinfo -l -i /path/to/your_iso_file.iso
```
-l: Long listing (shows more details).

-i /path/to/your_iso_file.iso: Specifies the input ISO file.

Look through the output. While it won't explicitly say "this is file #1", the sequential listing of files and their attributes (like block numbers) can give you a sense of their placement. If you used a sort file, the order here should reflect it. If you used numerical prefixes, you'll see them listed in that alphanumeric order.

Step 4: Unmount the ISO File
Once you're done checking, it's important to unmount the ISO file:

```
umount /mnt/iso_test
```
Step 5: Clean Up (Optional)
You can remove the temporary mount point directory:

```
rm -r /mnt/iso_test
```
By mounting the ISO and using ls -f, you'll get the most accurate representation of the file order as it was written to the image, confirming whether your genisoimage sorting (either via renaming or a sort file) was successful.
