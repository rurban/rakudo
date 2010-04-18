# TODO: how to make these subs private?
sub is-leap($year) {
    return False if $year % 4;
    return True  if $year % 100;
    $year % 400 == 0;
}

sub days-in-month($year, $month) {
    my @month-length = 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31;
    if ($month == 2) {
        is-leap($year) ?? 29 !! 28;
    } else {
        @month-length[$month-1];
    }
}

sub assert-valid-date($year, $month, $day) {
    die 'Invalid date: day < 1'     if $day < 1;
    die 'Invalid date: month < 1'   if $month < 1;
    die 'Invalid date: month > 12'  if $month > 12;
    my $dim = days-in-month($year, $month);
    if $day >  $dim {
        die "Invalid date: day > $dim";
    }
}

class Date {
    has Int $.year;
    has Int $.month;
    has Int $.day;

    has Int $.daycount = self!daycount-from-ymd($!year, $!month, $!day);

    method !daycount-from-ymd($y is copy, $m is copy, $d) {
        # taken from <http://www.merlyn.demon.co.uk/daycount.htm>
        if ($m < 3) {
            $m += 12;
            --$y;
        }
        return -678973 + $d + ((153 * $m - 2) div 5)
            + 365 * $y + ($y div 4)
            - ($y div 100)  + ($y div 400);
    }

    method !ymd-from-daycount($daycount) {
        # taken from <http://www.merlyn.demon.co.uk/daycount.htm>
        my $y = 0;
        my $m = 0;
        my $d = $daycount + 678881;
        my $t = ((4 * ($d + 36525)) div 146097) - 1;
        $y += 100 * $t;
        $d -= 36524 * $t + ($t +> 2);
        $t = ((4 * ($d + 366)) div 1461) - 1;
        $y += $t;
        $d -= 365 * $t + ($t +> 2);
        $m = (5 * $d + 2) div 153;
        $d -= (2 + $m * 153) div 5;
        if ($m > 9) {
            $m -= 12;
            $y++;
        }
        return $y, $m + 3, $d+1;
    }


    # TODO: checking for out-of-range errors
    multi method new($year, $month, $day) {
        assert-valid-date($year, $month, $day);
        self.bless(*, :$year, :$month, :$day);
    }
    multi method new(:$year, :$month, :$day) {
        assert-valid-date($year, $month, $day);
        self.bless(*, :$year, :$month, :$day);
    }

    multi method new(Str $date where { $date ~~ /
            ^ <[0..9]>**4 '-' <[0..9]>**2 '-' <[0..9]>**2 $
        /}) {
        my ($year, $month, $day) =  $date.split('-').map({ .Int });
        assert-valid-date($year, $month, $day);
        self.bless(*, :$year, :$month, :$day);
# RAKUDO: doesn't work yet - find out why
#        self.new(|$date.split('-'));
    }

    multi method new-from-daycount($daycount) {
        my ($year, $month, $day) = self!ymd-from-daycount($daycount);
        self.bless(*, :$year, :$month, :$day, :$daycount);
    }

    multi method today() {
        my $dt = ::DateTime.now();
        self.bless(*, :year($dt.year), :month($dt.month), :day($dt.day));
    }

    method day-of-week()   { 1 + (($!daycount + 2) % 7) }
    method leap-year()     { is-leap($.year) }
    method days-in-month() { days-in-month($.year, $.month) }

    multi method Str() {
        sprintf '%04d-%02d-%02d', $.year, $.month, $.day;
    }

    # arithmetics
    multi method succ() {
        Date.new-from-daycount($!daycount + 1);
    }
    multi method pred() {
        Date.new-from-daycount($!daycount - 1);
    }

    multi method perl() {
        "Date.new($.year.perl(), $.month.perl(), $.day.perl())";
    }

}

multi infix:<+>(Date $d, Int $x) is export {
    Date.new-from-daycount($d.daycount + $x)
}
multi infix:<+>(Int $x, Date $d) is export {
    Date.new-from-daycount($d.daycount + $x)
}
multi infix:<->(Date $d, Int $x) is export {
    Date.new-from-daycount($d.daycount - $x)
}
multi infix:<->(Date $a, Date $b) is export {
    $a.daycount - $b.daycount;
}
multi infix:<cmp>(Date $a, Date $b) is export {
    $a.daycount cmp $b.daycount
}
multi infix:«<=>»(Date $a, Date $b) is export {
    $a.daycount <=> $b.daycount
}
multi infix:<==>(Date $a, Date $b) is export {
    $a.daycount == $b.daycount
}
multi infix:<!=>(Date $a, Date $b) is export {
    $a.daycount != $b.daycount
}
multi infix:«<=»(Date $a, Date $b) is export {
    $a.daycount <= $b.daycount
}
multi infix:«<»(Date $a, Date $b) is export {
    $a.daycount < $b.daycount
}
multi infix:«>=»(Date $a, Date $b) is export {
    $a.daycount >= $b.daycount
}
multi infix:«>»(Date $a, Date $b) is export {
    $a.daycount > $b.daycount
}
