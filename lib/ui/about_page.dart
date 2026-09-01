// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// Package imports:
import 'package:url_launcher/url_launcher.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final yamlString = await rootBundle.loadString('pubspec.yaml');
      final yamlMap = loadYaml(yamlString);
      final version = yamlMap['version'] as String;
      setState(() {
        _version = version;
      });
    } catch (e) {
      setState(() {
        _version = AppLocalizations.of(context).unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(l10n.appTitle),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TitleText(l10n.about),
              Padding(
                padding: const EdgeInsets.only(
                    left: 7, right: 7, top: 13, bottom: 10),
                child: Text(
                  l10n.aboutDescription,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 10),
                child: Text(
                  l10n.aboutForkNote,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 5),
                child: Text(
                  l10n.aboutOriginalNote,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 15),
                child: Text(
                  l10n.version,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 5),
                child: Text(
                  _version.isEmpty ? l10n.loading : _version,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 15),
                child: Text(
                  l10n.github,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              _UrlText(
                  text: l10n.thisForkByWarreth,
                  url: 'https://github.com/warreth/OpenlibExtended'),
              _UrlText(
                  text: l10n.reportAnIssue,
                  url: 'https://github.com/warreth/OpenlibExtended/issues'),
              _UrlText(
                  text: l10n.originalProject,
                  url: 'https://github.com/dstark5/Openlib'),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 15),
                child: Text(
                  l10n.licence,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              _UrlText(
                  text: l10n.gplLicense,
                  url: 'https://www.gnu.org/licenses/gpl-3.0.en.html'),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlText extends StatelessWidget {
  const _UrlText({required this.text, required this.url});

  final String url;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 7, right: 7, top: 5),
      child: InkWell(
        onTap: () async {
          final l10n = AppLocalizations.of(context);
          final Uri uri = Uri.parse(url);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            final message = l10n.couldNotLaunch('$uri');
            // ignore: use_build_context_synchronously
            showSnackBar(context: context, message: message);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(
              width: 2,
            ),
            const Icon(
              Icons.launch,
              size: 17,
              color: Colors.blueAccent,
            )
          ],
        ),
      ),
    );
  }
}
