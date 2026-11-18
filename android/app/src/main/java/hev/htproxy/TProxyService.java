package hev.htproxy;

/** Default JNI contract of the pinned, source-built Hev tunnel. */
public final class TProxyService {
    static { System.loadLibrary("hev-socks5-tunnel"); }
    public static native boolean TProxyStartService(String path, int fd);
    public static native boolean TProxyStopService();
    public static native boolean TProxyIsRunning();
    public static native long[] TProxyGetStats();
}
