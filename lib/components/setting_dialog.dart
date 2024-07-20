import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/settings.dart';
import '../data/icon_lib.dart';
import '../data/color_lib.dart';

class SettingDialog {
  static Future<Settings?> showDialogText(BuildContext context, Settings me) async {
    //stdout.write('showDialogText() ${me.toJson().toString()}\n');

    String myName = me.name;
    PngString myPic = PngLib.getPngByName(me.pic);
    ColorString myColor = ColorLib.getColorByName(me.color);

    String myLocale = me.locale ?? 'en';


    return showDialog<Settings>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return SimpleDialog(title: const Text('Enter Name:'), children: <Widget>[
              Padding(
                  padding: const EdgeInsets.all(10.0), //  10 Pixel Abstand auf allen Seiten
                  child: Column(
                    children: [
                      //Name
                      TextFormField(
                        initialValue: myName,
                        maxLength: 15,
                        decoration: const InputDecoration(
                          hintText: 'Enter Name',
                        ),
                        onChanged: (value) {
                          myName = value;
                        },
                      ),
                      //Avatar
                      DropdownButton<PngString>(
                        value: myPic,
                        isExpanded: true,
                        onChanged: (value) {
                          if (value != null && value != myPic) {
                            setState(() {
                              myPic = value;
                            });
                          }
                        },
                        items: PngLib.pngStringList.map<DropdownMenuItem<PngString>>((PngString value) {
                          return DropdownMenuItem<PngString>(
                            value: value,
                            child: Row(children: [
                              Image.asset(
                                value.path,
                              ),
                              Text(
                                ' - ${value.name}',
                                overflow: TextOverflow.ellipsis, // default is .clip
                                maxLines: 1,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ]),
                          );
                        }).toList(),
                      ),
                      //Color
                      DropdownButton<ColorString>(
                        value: myColor,
                        isExpanded: true,
                        onChanged: (value) {
                          if (value != null && value != myColor) {
                            setState(() {
                              myColor = value;
                            });
                          }
                        },
                        items: ColorLib.colorStringList.map<DropdownMenuItem<ColorString>>((ColorString value) {
                          return DropdownMenuItem<ColorString>(
                              value: value,
                              child: Row(children: [
                                Text(
                                  ' - ${value.name}',
                                  selectionColor: myColor.color,
                                  overflow: TextOverflow.ellipsis, // default is .clip
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ]));
                        }).toList(),
                      ),

                      //language
                      DropdownButton<Locale>(
                        // Read the selected themeMode from the controller
                        value: Locale(myLocale),
                        // Call the updateThemeMode method any time the user selects a theme.
                        onChanged: (value) {
                          setState(() {
                            myLocale = value!.languageCode;
                          });
                        },
                        items:  [
                          DropdownMenuItem(
                            value: const Locale('de'),
                            child: Text(AppLocalizations.of(context)!.german),
                          ),
                          DropdownMenuItem(
                            value: const Locale('en'),
                            child: Text(AppLocalizations.of(context)!.english),
                          ),
                        ],
                      ),


                    ],
                  )),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(
                          context,
                          Settings(
                              publicKey: me.publicKey,
                              name: myName,
                              pic: myPic.name,
                              color: myColor.name,
                              privateKey: me.privateKey));
                    },
                    child: const Text('OK'),
                  ),
                  SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(context, null);
                    },
                    child: const Text('Cancel'),
                  )
                ],
              )
            ]);
          });
        });
  }
}
