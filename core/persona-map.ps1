# persona-map.ps1
# loginUserNo = 로그인 샘플 JSON 번호
# targetUserId = DB users.id

$Global:GooUsers = @(
    @{ loginUserNo = 16; targetUserId = 5;  persona = "steady";      label = "u16"  }
    @{ loginUserNo = 17; targetUserId = 6;  persona = "immersive";   label = "u17"  }
    @{ loginUserNo = 18; targetUserId = 7;  persona = "burst";       label = "u18"  }
    @{ loginUserNo = 20; targetUserId = 9;  persona = "gap";         label = "u20"  }
    @{ loginUserNo = 21; targetUserId = 10; persona = "recovery";    label = "u21"  }
    @{ loginUserNo = 101; targetUserId = 13; persona = "lowactive";  label = "u101" }
)