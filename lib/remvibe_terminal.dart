/// Independent native terminal sessions; no UI, networking or Fleet dependency.
library;

export 'src/remvibe_terminal.dart'
    show RemVibeTerminal, RemVibeTerminalSession, TerminalNativeException,
        TerminalNativeLibraryLoadException;

export 'src/session/terminal_session_service.dart' show
    HostedTerminalProcess, HostedTerminalProcessFactory,
    HostedTerminalInfo, HostedTerminalAttachment, TerminalOutputFrame,
    HostedTerminalCommandActivity, TerminalSessionService;

export 'src/session/terminal_events.dart'
    show TerminalCommandState, TerminalStateEventKind, TerminalStateEvent,
        TerminalStreamEvent, TerminalEventSource, TerminalHandlerRegistration,
        TerminalStateCallback, TerminalStreamCallback;

export 'src/session/terminal_session_service.dart' show TerminalSession;

export 'src/session/terminal_handler.dart'
    show TerminalHandler, TerminalHandlerLocal;
