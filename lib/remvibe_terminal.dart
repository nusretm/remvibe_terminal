/// Independent native terminal sessions; no UI, networking or Fleet dependency.
library;

export 'src/remvibe_terminal.dart'
    show RemVibeTerminal, RemVibeTerminalSession, TerminalNativeException,
        TerminalNativeLibraryLoadException;

export 'src/session/terminal_session_pool.dart' show
    HostedTerminalProcess, HostedTerminalProcessFactory,
    HostedTerminalInfo, HostedTerminalAttachment, TerminalOutputFrame,
    HostedTerminalCommandActivity, TerminalSessionPool;
