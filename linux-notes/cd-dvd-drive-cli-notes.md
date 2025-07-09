# Setup CD/DVD Burning Tools on NAS Proxmox Host:
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
genisoimage -o /path/to/my_disc.iso -R -J /path/to/source_data/
```
Replace /path/to/my_disc.iso with the desired output path and filename for your ISO.

Replace /path/to/source_data/ with the directory containing the files you want to burn.

-R: Rock Ridge extensions (for long filenames, UNIX permissions, etc.)

-J: Joliet extensions (for compatibility with Windows long filenames)

You might also add -V "DISC_LABEL" to set a volume label.

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

## Here's a step-by-step guide to read and copy data files (like documents, images, software installers) and MP3s from a CD/DVD on your Proxmox host's command line:

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
