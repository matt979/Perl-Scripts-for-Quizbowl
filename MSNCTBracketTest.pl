use strict;

my ($SEPARATOR, $NEWLINE) = ("\t", "\n");

my $FN = "msnct128rounds.txt"; #FIXME: should be an argument
my $NUM_ROUNDS = -1; #set automatically via schedule parsing
my $NUM_GAMES_PER_TEAM = 8;
my $NUM_SIMULATIONS = 10000;
my $BYE = "BYE";

#win cutoffs for the playoff top bracket and loser's bracket
#values below zero are never satisified (rather than always satisfied)
my $PLAYOFF_WIN_CUTOFF = 5; 
my $PLAYOFF_WIN_CUTOFF2 = -1; 

#for the schedule setup, invariant after the schedule is loaded
my %h_card_round_to_match = ();
my %h_room_round_to_match = ();
my %h_card_to_game_count = ();
my %h_room_to_type = ();

#for the monte carlo simulation, intrinsic to each iteration
my %h_card_to_team_object = ();
my %h_initial_teams_to_game_count = ();
my $n_repeat_count = 0;

#for the monte carlo simulation, cumulative
my %h_playoff_count_to_freq = ();
my %h_match_to_repeat_freq = ();
my %h_match_to_win_disparity_freq = ();
my %h_match_to_bubble_freq = ();
my %h_repeat_count_to_freq = ();

open(SANITY, ">".$FN."-Sanity_Checks.txt");
open(MONTECARLO, ">".$FN."-MonteCarlo.txt");
load_the_schedule();
sanity_check_the_schedule();
monte_carlo_the_schedule();
print_the_results();
close(MONTECARLO);
close(SANITY);

sub load_the_schedule {
	open(IN, "<", $FN) or die("Could not open file");
	while(<IN>) {
		chomp($_);
		load_the_game_room($_);
	}
	close(IN);
}

sub load_the_game_room {
	my @a = split(/$SEPARATOR/, $_[0]);
	
	if(exists $h_room_to_type{$a[0]}) {
		die("Duplicate game room name ".$a[0]);
	} else {
		$h_room_to_type{$a[0]} = $a[1];
	}
	
	for(my $i = 1; $i * 2 < @a; $i++) {
		load_the_match($i, $a[0], $a[(2*$i)], $a[(2*$i)+1]);
		if($NUM_ROUNDS < $i) {
			$NUM_ROUNDS = $i;
		}
	}
}

sub load_the_match {
	my ($round, $room, $t1, $t2) = @_;
	return if($t1 eq "" && $t2 eq "");
	die() if($t1 eq "" || $t2 eq "");
	
	$h_card_to_game_count{$t1}++;
	$h_card_to_game_count{$t2}++;
	
	my $match_object = {
		 ROUND => $round
		,ROOM  => $room
		,CARD1 => $t1
		,CARD2 => $t2
		,ERROR_LABEL => $round." - ".$room." (".$t1." vs ".$t2.")"
	};

	if(exists $h_card_round_to_match{join($SEPARATOR,$t1,$round)}) {
		die("Card $t1 already has a match in round $round");
	} else {
		$h_card_round_to_match{join($SEPARATOR,$t1,$round)} = $match_object;
	}
	if(exists $h_card_round_to_match{join($SEPARATOR,$t2,$round)}) {
		die("Card $t2 already has a match in round $round");
	} else {
		$h_card_round_to_match{join($SEPARATOR,$t2,$round)} = $match_object;
	}
	if(exists $h_room_round_to_match{join($SEPARATOR,$room,$round)}) {
		die("Room $room already has a match in round $round");
	} else {
		$h_room_round_to_match{join($SEPARATOR,$room,$round)} = $match_object;
	}
}

sub sanity_check_the_schedule {
	#double-booked teams: taken care of on load
	
	#does each team have the right number of games?
	foreach(keys %h_card_to_game_count) {
		if($h_card_to_game_count{$_} != $NUM_GAMES_PER_TEAM) {
			die("Card ".$_." has the wrong number of games.");
		}
	}
	
	#how are the room transitions
	print SANITY "Room Transitions".$NEWLINE;
	print SANITY join($SEPARATOR,"Card","Round","Previous Room","This Room").$NEWLINE;
	foreach(sort {$a<=>$b} keys %h_card_to_game_count) {
		my $card = $_;
		my @a = ();
		push(@a, $card);
		for(my $i = 1; $i <= $NUM_ROUNDS; $i++) {
			if(exists $h_card_round_to_match{join($SEPARATOR,$card,$i)}) {
				push(@a, $h_card_round_to_match{join($SEPARATOR,$card,$i)}->{ROOM});
			} else {
				push(@a, $BYE);
			}
		}
		
		for(my $i = 2; $i < @a; $i++) {
			check_room_transition($a[0], $i, $a[$i-1], $a[$i]);
		}
	}
	
	#are there any idle game rooms
	print SANITY "Idle Game Rooms (if any)".$NEWLINE;
	print SANITY join($SEPARATOR, "Round", "Room").$NEWLINE;
	for(my $i = 1; $i < $NUM_ROUNDS; $i++) {
		foreach(keys %h_room_to_type) {
			log_empty_room($i,$_) unless(exists $h_room_round_to_match{join($SEPARATOR,$_,$i)});
		}
	}
}

sub check_room_transition {
	my($card, $round, $old, $new) = ($_[0], $_[1], $_[2], $_[3]);
	if($old eq "BYE" && $new eq "BYE") {
		log_odd_room_transition($card, $round, "BYE", "BYE");
		return;
	} elsif($old eq "BYE" || $new eq "BYE") {
		return;
	}

	my $old_type = $h_room_to_type{$old};
	my $new_type = $h_room_to_type{$new};
	log_odd_room_transition($card, $round, $old, $new) unless($old_type eq $new_type);
}

sub log_empty_room {
	print SANITY join($SEPARATOR,@_).$NEWLINE;
}

sub log_odd_room_transition {
	print SANITY join($SEPARATOR,@_).$NEWLINE;
}

sub monte_carlo_the_schedule {
	for(my $i = 0; $i < $NUM_SIMULATIONS; $i++) {
		do_a_monte_carlo_iteration();
		if($i % 50 == 0) {
			print $i."\n";
		}
	}
}

sub do_a_monte_carlo_iteration {
	initialize_monte_carlo_iteration();
	run_monte_carlo_iteration();
	cleanup_monte_carlo_iteration();
}

sub initialize_monte_carlo_iteration {
	$n_repeat_count = 0;
	%h_card_to_team_object = ();
	%h_initial_teams_to_game_count = ();
	foreach(sort {$a<=>$b} keys %h_card_to_game_count) {
		my $team_object = {
			  ORIGINAL_CARD => $_
			, CURRENT_CARD  => $_
			, GAMES         => 0
			, WINS          => 0
			, LOSSES        => 0
		};
		$h_card_to_team_object{$_} = $team_object;
	}
}

sub run_monte_carlo_iteration {
	for(my $i = 1; $i <= $NUM_ROUNDS; $i++) {
		run_monte_carlo_iteration_round($i);
	}
}

sub run_monte_carlo_iteration_round {
	my $n = $_[0];
	foreach(keys %h_room_to_type) {
		if(exists $h_room_round_to_match{join($SEPARATOR,$_,$n)}) {
			run_monte_carlo_one_match($h_room_round_to_match{join($SEPARATOR,$_,$n)});
		}
	}
}

sub run_monte_carlo_one_match {
	my $match_object  = $_[0];
	my $n_first_card  = $match_object->{CARD1};
	my $n_second_card = $match_object->{CARD2};
	my $first_team_object  = $h_card_to_team_object{$n_first_card};
	my $second_team_object = $h_card_to_team_object{$n_second_card};
	
	log_games_played_sev($match_object) unless($first_team_object->{GAMES} == $second_team_object->{GAMES});
	log_wins_disparity_sev($match_object) unless(abs($first_team_object->{WINS} - $second_team_object->{WINS}) <= 1);
	log_wins_disparity($match_object) unless($first_team_object->{WINS} == $second_team_object->{WINS});

	my $original_card_key = "";
	my $first_original_card = $first_team_object->{ORIGINAL_CARD};
	my $second_original_card = $second_team_object->{ORIGINAL_CARD};
	if($first_original_card < $second_original_card) {
		$original_card_key = join($SEPARATOR,$first_original_card,$second_original_card);
	} else {
		$original_card_key = join($SEPARATOR,$second_original_card,$first_original_card);
	}
	
	log_repeat_sev($match_object) if($h_initial_teams_to_game_count{$original_card_key} > 1);
	log_repeat($match_object) if($h_initial_teams_to_game_count{$original_card_key} > 0);
	
	log_bubble_game($match_object) if(bubble_team($first_team_object) || bubble_team($second_team_object));
	
	$first_team_object->{GAMES}++;
	$second_team_object->{GAMES}++;
	$h_initial_teams_to_game_count{$original_card_key}++;
	if(rand() > .5) {
		$first_team_object->{WINS}++;
		$second_team_object->{LOSSES}++;
	} else {
		$first_team_object->{LOSSES}++;
		$second_team_object->{WINS}++;	
		$first_team_object->{CURRENT_CARD} = $n_second_card;
		$second_team_object->{CURRENT_CARD} = $n_first_card;
		$h_card_to_team_object{$n_first_card} = $second_team_object;
		$h_card_to_team_object{$n_second_card} = $first_team_object;
	}
}

sub log_repeat {
	$n_repeat_count++;
	$h_match_to_repeat_freq{$_[0]->{ERROR_LABEL}}++;
}

sub log_repeat_sev {
	die("Teams facing each other 3x issue for ".$_[0]->{ERROR_LABEL});
}

sub log_wins_disparity {
	$h_match_to_win_disparity_freq{$_[0]->{ERROR_LABEL}}++;
}

sub log_bubble_game {
	$h_match_to_bubble_freq{$_[0]->{ERROR_LABEL}}++;
}

sub log_wins_disparity_sev {
	die("Wins disparity issue for ".$_[0]->{ERROR_LABEL});
}

sub log_games_played_sev {
	die("Games played issue for ".$_[0]->{ERROR_LABEL});
}

sub bubble_team {
	my $o = $_[0];
	if($o->{GAMES} + 1 == $NUM_GAMES_PER_TEAM
		&& ($o->{WINS} + 1 == $PLAYOFF_WIN_CUTOFF ||
		    $o->{WINS} + 1 == $PLAYOFF_WIN_CUTOFF2)) {
		return 1;
	} else {
		return 0;
	}
}

sub cleanup_monte_carlo_iteration {
	my $wb = 0;
	my $lb = 0;
	foreach(sort {$a<=>$b} keys %h_card_to_game_count) {
		my $n_final_win_total = $h_card_to_team_object{$_}->{WINS};
		if($PLAYOFF_WIN_CUTOFF > 0 && $n_final_win_total >= $PLAYOFF_WIN_CUTOFF) {
			$wb++;
		} elsif($PLAYOFF_WIN_CUTOFF2 > 0 && $n_final_win_total >= $PLAYOFF_WIN_CUTOFF2) {
			$lb++;
		}
	}
	$h_playoff_count_to_freq{join($SEPARATOR,$wb,$lb)}++;
	$h_repeat_count_to_freq{$n_repeat_count}++;
}

sub print_the_results {
	print MONTECARLO "NUMBER OF SIMULATIONS RUN: ".$NUM_SIMULATIONS.$NEWLINE;
	print MONTECARLO $NEWLINE;
	
	print MONTECARLO "PLAYOFF TEAM COUNTS:".$NEWLINE;
	print MONTECARLO join($SEPARATOR,"WB","LB","Occurrences").$NEWLINE;
	foreach(sort keys %h_playoff_count_to_freq) {
		print MONTECARLO join($SEPARATOR,$_,$h_playoff_count_to_freq{$_}).$NEWLINE;
	}
	print MONTECARLO $NEWLINE;
	
	print MONTECARLO "REMATCH COUNTS PER SIMULATION:".$NEWLINE;
	print MONTECARLO join($SEPARATOR,"Rematches","Occurrences").$NEWLINE;
	foreach(sort keys %h_repeat_count_to_freq) {
		print MONTECARLO join($SEPARATOR,$_,$h_repeat_count_to_freq{$_}).$NEWLINE;
	}
	print MONTECARLO $NEWLINE;
	
	print MONTECARLO "GAMES WITH A WIN DISPARITY:".$NEWLINE;
	foreach(sort keys %h_match_to_win_disparity_freq ) {
		print MONTECARLO join($SEPARATOR,$_,$h_match_to_win_disparity_freq{$_}).$NEWLINE;
	}
	print MONTECARLO $NEWLINE;
	
	print MONTECARLO "GAMES WITH A REPEAT:".$NEWLINE;
	foreach(sort keys %h_match_to_repeat_freq ) {
		print MONTECARLO join($SEPARATOR,$_,$h_match_to_repeat_freq{$_}).$NEWLINE;
	}
	print MONTECARLO $NEWLINE;
	
	print MONTECARLO "GAMES WITH BUBBLE TEAM(s):".$NEWLINE;
	foreach(sort keys %h_match_to_bubble_freq ) {
		print MONTECARLO join($SEPARATOR,$_,$h_match_to_bubble_freq{$_}).$NEWLINE;
	}
	print MONTECARLO $NEWLINE;
}
