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
            CloseHandle(input);
            CloseHandle(output);
        }
    }
}
