using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class PowerFlowSshAskPass
{
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint ShareRead = 0x00000001;
    private const uint ShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private static readonly IntPtr InvalidHandle = new IntPtr(-1);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateFile(
        string name, uint access, uint share, IntPtr security, uint creation,
        uint flags, IntPtr template);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool ReadConsole(
        IntPtr input, [Out] char[] buffer, uint count, out uint read, IntPtr control);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool WriteConsole(
        IntPtr output, string text, uint count, out uint written, IntPtr reserved);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    // ── Console input mode ───────────────────────────────────────────────────
    // A console handle arrives with ENABLE_ECHO_INPUT and ENABLE_LINE_INPUT already ON.
    // Without clearing them the console prints every keystroke ITSELF, so the password
    // appeared in cleartext — and ENABLE_LINE_INPUT made ReadConsole block until Enter, so
    // this program's own masking arrived afterwards, in a block, on the line below. Both
    // observed symptoms came from these two flags.
    //
    // The Linux sibling (platform/linux/helpers/powerflow-ssh-askpass.sh) has always done
    // this correctly: `stty -g` to save, `stty -echo` to clear, and a restore from an
    // EXIT/HUP/INT/TERM trap. This is the same three steps in Win32 terms.
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleMode(IntPtr handle, out uint mode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleMode(IntPtr handle, uint mode);

    private const uint EnableEchoInput = 0x0004;
    private const uint EnableLineInput = 0x0002;

    private static bool WriteTerminal(IntPtr output, string text)
    {
        uint written;
        return WriteConsole(output, text, (uint)text.Length, out written, IntPtr.Zero);
    }

    public static int Main()
    {
        string alias = Environment.GetEnvironmentVariable("POWERFLOW_SRV_ALIAS") ?? "server";
        IntPtr input = CreateFile("CONIN$", GenericRead | GenericWrite, ShareRead | ShareWrite,
            IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        IntPtr output = CreateFile("CONOUT$", GenericRead | GenericWrite, ShareRead | ShareWrite,
            IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);

        if (input == InvalidHandle || output == InvalidHandle)
        {
            if (input != InvalidHandle) CloseHandle(input);
            if (output != InvalidHandle) CloseHandle(output);
            return 1;
        }

        // Save the mode BEFORE changing it, and only claim it is restorable if the read
        // succeeded — restoring a mode that was never captured would set the console to 0,
        // which is worse than leaving it alone.
        uint originalMode;
        bool modeSaved = GetConsoleMode(input, out originalMode);
        if (modeSaved)
        {
            // Clearing ENABLE_LINE_INPUT as well as ENABLE_ECHO_INPUT is deliberate: it is
            // what makes ReadConsole return per keystroke, so the '*' appears AS the user
            // types rather than in a block after Enter.
            SetConsoleMode(input, originalMode & ~(EnableEchoInput | EnableLineInput));
        }

        var password = new List<char>();
        try
        {
            WriteTerminal(output, "Password for '" + alias + "': ");
            var buffer = new char[1];
            while (true)
            {
                uint read;
                if (!ReadConsole(input, buffer, 1, out read, IntPtr.Zero) || read == 0)
                {
                    WriteTerminal(output, Environment.NewLine);
                    return 1;
                }

                char value = buffer[0];
                if (value == '\r' || value == '\n')
                    break;
                if (value == (char)3 || value == (char)4)
                {
                    WriteTerminal(output, Environment.NewLine);
                    return 1;
                }
                if (value == '\b')
                {
                    if (password.Count > 0)
                    {
                        password.RemoveAt(password.Count - 1);
                        WriteTerminal(output, "\b \b");
                    }
                    continue;
                }

                password.Add(value);
                WriteTerminal(output, "*");
            }
            WriteTerminal(output, Environment.NewLine);

            char[] secret = password.ToArray();
            try
            {
                using (var writer = new StreamWriter(
                    Console.OpenStandardOutput(), new UTF8Encoding(false), 1024, false))
                {
                    writer.Write(secret);
                    writer.Write('\n');
                }
            }
            finally
            {
                Array.Clear(secret, 0, secret.Length);
            }
            return 0;
        }
        finally
        {
            for (int i = 0; i < password.Count; i++) password[i] = '\0';
            password.Clear();

            // Restore BEFORE closing the handle, and on every exit path — the early returns
            // for Ctrl+C, Ctrl+D and a failed read all pass through here. A helper that exits
            // with echo still disabled hands back a console that looks dead: the user types
            // and nothing appears. That is the one failure mode worse than the bug being fixed.
            if (modeSaved) SetConsoleMode(input, originalMode);

            CloseHandle(input);
            CloseHandle(output);
        }
    }
}
