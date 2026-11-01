import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlib/services/reader_apps.dart';
import 'package:openlib/state/state.dart'
    show
        readerPreferenceProvider,
        readerPreferencesProvider,
        installedReadersProvider;

class ReaderAppSetting extends ConsumerStatefulWidget {
  const ReaderAppSetting({super.key, required this.format});
  final String format;

  @override
  ConsumerState<ReaderAppSetting> createState() => _ReaderAppSettingState();
}

class _ReaderAppSettingState extends ConsumerState<ReaderAppSetting> {
  bool _saving = false;

  Future<void> _select(String reader) async {
    setState(() => _saving = true);
    try {
      await ref.read(readerPreferencesProvider).save(widget.format, reader);
      ref.invalidate(readerPreferenceProvider(widget.format));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).readerSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preference = ref.watch(readerPreferenceProvider(widget.format));
    final installed = ref.watch(installedReadersProvider(widget.format));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: preference.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => TextButton(
            onPressed: () =>
                ref.invalidate(readerPreferenceProvider(widget.format)),
            child: Text(l10n.readerLoadFailed)),
        data: (selected) {
          final choices = [
            ReaderApp(id: 'internal', label: l10n.builtInReader),
            ReaderApp(
                id: 'ask',
                label: ReaderApps.showsExternalChooser
                    ? l10n.askEveryTime
                    : l10n.systemDefaultReader),
            ...?installed.valueOrNull,
          ];
          final unavailable = !choices.any((choice) => choice.id == selected);
          return DropdownButtonFormField<String>(
            key: ValueKey('${widget.format}:$selected'),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.readerForFormat(widget.format.toUpperCase()),
              helperText: installed.hasError
                  ? l10n.readerListFailed
                  : installed.isLoading
                      ? l10n.readerListLoading
                      : l10n.readerOpenHint,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final choice in choices)
                DropdownMenuItem(
                    value: choice.id,
                    child: Text(choice.label, overflow: TextOverflow.ellipsis)),
              if (unavailable)
                DropdownMenuItem(
                    value: selected,
                    enabled: false,
                    child: Text(installed.isLoading
                        ? l10n.readerLoading
                        : l10n.readerUnavailable)),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) _select(value);
                  },
          );
        },
      ),
    );
  }
}
