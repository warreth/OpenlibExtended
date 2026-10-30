/// Raised for anything the user can fix by changing the invocation.
class CliUsageException implements Exception {
  final String message;
  CliUsageException(this.message);
  @override
  String toString() => message;
}

/// Parsed and lightly validated command line arguments.
///
/// Hand-rolled because the project avoids adding a dependency for one binary.
class CliOptions {
  static const Set<String> _valueFlags = {
    'base-url',
    'timeout',
    'output',
    'ext',
    'lang',
    'sort',
    'content',
    'author',
    'publisher',
    'year-from',
    'year-to',
    'page',
    'limit',
  };

  static const Set<String> _boolFlags = {'help', 'quiet'};

  static const Set<String> _globalValueFlags = {'base-url', 'timeout'};

  static const Map<String, Set<String>> _commandValueFlags = {
    'search': {
      'ext',
      'lang',
      'sort',
      'content',
      'author',
      'publisher',
      'year-from',
      'year-to',
      'page',
      'limit',
    },
    'info': <String>{},
    'download': {'output'},
    'mirrors': <String>{},
    'version': <String>{},
  };

  final String? command;
  final List<String> positionals;
  final Map<String, String> values;
  final Set<String> flags;

  const CliOptions._(this.command, this.positionals, this.values, this.flags);

  static CliOptions parse(List<String> arguments) {
    final positionals = <String>[];
    final values = <String, String>{};
    final flags = <String>{};
    var endOfOptions = false;

    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (!endOfOptions && arg == '--') {
        endOfOptions = true;
        continue;
      }
      if (!endOfOptions && arg.startsWith('--')) {
        var name = arg.substring(2);
        if (name.isEmpty) {
          throw CliUsageException('Invalid option: --');
        }

        String? inline;
        final eq = name.indexOf('=');
        if (eq != -1) {
          inline = name.substring(eq + 1);
          name = name.substring(0, eq);
        }

        if (_valueFlags.contains(name)) {
          final value =
              inline ?? (i + 1 < arguments.length ? arguments[++i] : null);
          if (value == null || value.isEmpty) {
            throw CliUsageException('Option --$name needs a value');
          }
          values[name] = value;
        } else if (_boolFlags.contains(name)) {
          if (inline != null) {
            throw CliUsageException('Option --$name does not take a value');
          }
          flags.add(name);
        } else {
          throw CliUsageException('Unknown option: --$name');
        }
        continue;
      }
      positionals.add(arg);
    }

    final command = positionals.isEmpty ? null : positionals.first;
    final rest =
        positionals.length > 1 ? positionals.sublist(1) : const <String>[];
    final options = CliOptions._(command, rest, values, flags);
    options._validateCommand();
    return options;
  }

  String? value(String name) => values[name];

  bool flag(String name) => flags.contains(name);

  String requirePositional(int index, String message) {
    if (index >= positionals.length) throw CliUsageException(message);
    return positionals[index];
  }

  int intValue(
    String name, {
    required int defaultValue,
    int min = 0,
    int max = 1 << 31,
  }) {
    final raw = values[name];
    if (raw == null) return defaultValue;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < min || parsed > max) {
      throw CliUsageException(
          'Option --$name must be an integer between $min and $max');
    }
    return parsed;
  }

  void _validateCommand() {
    final command = this.command;
    if (command == null) return;

    final allowed = <String>{
      ..._globalValueFlags,
      ...?_commandValueFlags[command],
    };
    for (final name in values.keys) {
      if (!allowed.contains(name)) {
        throw CliUsageException('Option --$name is not valid for $command');
      }
    }

    if (flag('help')) return;

    switch (command) {
      case 'search':
        _requirePositionals(1, 'search needs one query');
        break;
      case 'info':
        _requirePositionals(1, 'info needs an md5 or book URL');
        break;
      case 'download':
        _requirePositionals(1, 'download needs an md5 or book URL');
        break;
      case 'mirrors':
      case 'version':
        _requirePositionals(0, '$command takes no arguments');
        break;
    }

    final baseUrl = value('base-url');
    if (baseUrl != null) {
      final uri = Uri.tryParse(baseUrl);
      if (uri == null ||
          !(uri.isScheme('http') || uri.isScheme('https')) ||
          uri.host.isEmpty) {
        throw CliUsageException(
            'Option --base-url must be an http(s) URL with a host');
      }
    }

    for (final name in const ['year-from', 'year-to']) {
      final raw = value(name);
      if (raw != null && !RegExp(r'^\d{1,4}$').hasMatch(raw)) {
        throw CliUsageException('Option --$name must be a year');
      }
    }
  }

  void _requirePositionals(int count, String message) {
    if (positionals.length != count) throw CliUsageException(message);
  }
}
