

class PngString {
  String name;
  String path;
  PngString(this.name, this.path);
}

class PngLib {
  static final pngStringList = [
    PngString('avatar1', 'assets/avatare/avatar1.png'),
    PngString('avatar2', 'assets/avatare/avatar2.png'),
    PngString('avatar3', 'assets/avatare/avatar3.png'),
    PngString('avatar4', 'assets/avatare/avatar4.png'),
    PngString('avatar5', 'assets/avatare/avatar5.png'),
    PngString('avatar6', 'assets/avatare/avatar6.png'),
    PngString('avatar7', 'assets/avatare/avatar7.png'),
    PngString('avatar8', 'assets/avatare/avatar8.png'),
    PngString('avatar9', 'assets/avatare/avatar9.png'),
    PngString('avatar10', 'assets/avatare/avatar10.png'),
    PngString('avatar11', 'assets/avatare/avatar11.png'),
    PngString('avatar12', 'assets/avatare/avatar12.png'),
    PngString('avatar13', 'assets/avatare/avatar13.png'),
    PngString('avatar14', 'assets/avatare/avatar14.png'),
    PngString('avatar15', 'assets/avatare/avatar15.png'),
    PngString('avatar16', 'assets/avatare/avatar16.png'),
    PngString('avatar17', 'assets/avatare/avatar17.png'),
    PngString('avatar18', 'assets/avatare/avatar18.png'),
    PngString('avatar19', 'assets/avatare/avatar19.png'),
    PngString('avatar20', 'assets/avatare/avatar20.png'),
    PngString('avatar21', 'assets/avatare/avatar21.png'),
    PngString('avatar22', 'assets/avatare/avatar22.png'),
    PngString('avatar23', 'assets/avatare/avatar23.png'),
    PngString('avatar24', 'assets/avatare/avatar24.png'),
    PngString('avatar25', 'assets/avatare/avatar25.png'),
    PngString('avatar26', 'assets/avatare/avatar26.png'),
    PngString('avatar27', 'assets/avatare/avatar27.png'),
    PngString('avatar28', 'assets/avatare/avatar28.png'),
    PngString('avatar29', 'assets/avatare/avatar29.png'),
    PngString('avatar30', 'assets/avatare/avatar30.png'),
    PngString('avatar31', 'assets/avatare/avatar31.png'),
    PngString('avatar32', 'assets/avatare/avatar32.png'),
    PngString('avatar33', 'assets/avatare/avatar33.png'),
    PngString('avatar34', 'assets/avatare/avatar34.png'),
    PngString('avatar35', 'assets/avatare/avatar35.png'),
    PngString('avatar36', 'assets/avatare/avatar36.png'),
  ];
  static PngString getPngByName(String name) {
    //stdout.write('getPngByName $name\n');
    return pngStringList.firstWhere((element) => element.name == name,
        orElse: () => pngStringList[0]);
  }
}
