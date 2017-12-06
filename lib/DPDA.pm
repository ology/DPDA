package DPDA;

# ABSTRACT: Dimensional Personality Disorder Assessment

use Dancer2;
use GD::Graph::bars;

our $VERSION = '0.01';

=head1 NAME

DPDA - Dimensional Personality Disorder Assessment

=head1 DESCRIPTION

A C<DPDA> is a web quiz for the assessment of personality disorders.

=head1 ROUTES

=head2 /question

Question page.

Method: get

=cut

get '/question' => sub {
    my $progress = query_parameters->get('progress') || 1;

    my $history;
    if ( $progress == 1 ) {
        cookie( history => '' )
    }
    else {
        $history = cookie('history');
        $history = [ split /,/, $history ]
            if $history;
    }
    my %history = map { split /\|/, $_ } @$history
        if $history;

    my @quiz = _load_quiz();

    my ( $question_num, $question_text ) = _get_question( \@quiz, \%history );

    template 'question' => {
        question_num    => $question_num,
        question_text   => $question_text,
        history         => $history,
        progress        => $progress,
        total_questions => scalar(@quiz),
    };
};

=head2 /quiz

Quiz submission.

Method: post

=cut

post '/quiz' => sub {
    my $question = body_parameters->get('question');
    my $answer   = body_parameters->get('answer');
    my $progress = body_parameters->get('progress');

    my $history = cookie('history');
    my %history;
    if ( $history || $answer ) {
        @history{ split /,/, $history } = undef;
        $history{ "$question|$answer" } = undef;
        cookie( history => join( ',', keys %history ) );
    }

    $progress++;

    my @quiz = _load_quiz();

    if ( $progress > @quiz ) {
        redirect '/chart';
    }
    else {
        redirect '/question?progress=' . $progress;
    }
};

=head2 /chart

Quiz results.

Method: get

=cut

get '/chart' => sub {
    my $history = cookie('history');
    my %history;
    if ( $history ) {
        $history = [ split /,/, $history ];
        %history = map { split /\|/, $_ } @$history;
    }

    my @quiz = _load_quiz();

    my @response = (
      'Strongly disagree',
      'Disagree',
      'Maybe',
      'Agree',
      'Strongly agree',
      '','','','',''
    );

    my ( %number, %order, %results, %average, %discord, $category );

    _calc_results( \@quiz, \@response, \%history, \%results, \%discord );

    _order_category( \%order, \@quiz );

    # Calculate the number of questions per category
    for $category ( keys %results ) {
        $number{$category} = grep { /^$category?.*$/ } @quiz;
    }

    # Calculate the average score for each category
    %average = map { $_ => $results{$_} / $number{$_} } keys %results;
    %average = map { $_ => sprintf( '%.2f', $average{$_} ) } keys %average;

    # Calculate the average discord between +/- questions
    %discord = map { $_ => ( @response * $discord{$_} / ( $number{$_} / 2 ) ) / ( @response - 1 ) } keys %discord;
    %discord = map { $_ => sprintf( '%.2f', $discord{$_} ) } keys %discord;

    my $chart = _draw_chart( scalar @response, \%order, \%average, \%discord );

    template 'chart' => {
        order   => \%order,
        average => \%average,
        discord => \%discord,
        chart   => $chart,
    };
};

get '/overview' => sub {
    template 'overview' => {};
};

get '/sample' => sub {
    template 'sample' => {};
};

sub _load_quiz {
    my @quiz;
    my $file = 'dpda-questions.txt';
    open my $fh, '<', $file or die "Can't read $file: $!";
    while ( my $line = <$fh> ) {
        chomp $line;
        push @quiz, $line;
    }
    close $fh;
    return @quiz;
}

sub _get_question {
    my ( $questions, $history ) = @_;

    my $question_num = int rand @$questions;
    my $question = $questions->[$question_num];
    do {
        $question_num = int rand @$questions;
        $question = $questions->[$question_num];
    } if exists $history->{$question};

    my $question_text = [ split /\|/, $question ]->[1];

    $question_num++;

    return $question_num, $question_text;
}

sub _calc_results {
  my ( $quiz, $response, $history, $results, $discord ) = @_;

  my ( $category, $inv, $next );

  for my $key (keys %$history) {
        my $val = $history->{$key};

        if ( ( $key / 2 ) =~ /\./ ) {
            # Calculate with the question parameters
            ( $category, undef, $inv ) = split /\s+/, ( split /\|/, $quiz->[ $key - 1 ] )[0];

            $val = _invert_neg( scalar @$response, $inv, $val );
            #print br('Q#, Cat, Inv, Val:', $key, $category, $inv, $val), "\n";

            $results->{$category} += $val;

            # ..And again for the next (discord) question
            $next = $history->{$key + 1};
            $inv  = ( split /\s+/, ( split /\|/, $quiz->[$key] )[0] )[-1];
            $next = _invert_neg( scalar @$response, $inv, $next );
            #print br('Q#, Cat, Inv, Val:', $key + 1, $category, $inv, $next), "\n";

            $results->{$category} += $next;

            $discord->{$category} += abs( $val - $next );
        }
    }
}

sub _invert_neg {
    my ( $size, $flag, $val ) = @_;

    $flag eq '-' ? return $size - ($val - 1)
                 : return $val;
}

sub _order_category {
    my ( $order, $quiz ) = @_;

    my $next = 1;

    for my $category (@$quiz) {
        $category =~ s/^(\w+).*$/$1/;
        chomp $category;

        $order->{$category} = $next++
            unless exists $order->{$category};
        #print 'Category, Order: ', "'$category'", ' => ', $order->{$category}, br, "\n";
    }
}

sub _draw_chart {
    my ( $size, $order, $results, $discord ) = @_;

    my $graph = GD::Graph::bars->new();
    $graph->set(
        title         => 'Results',
        x_label       => 'Categories',
        y_label       => 'Value',
        y_max_value   => $size,
        y_tick_number => $size,
        y_label_skip  => 1,
    ) or die "Can't set graph: ", $graph->error;

    my @names = sort { $order->{$a} <=> $order->{$b} } keys %$order;

    my @results = map { $results->{$_} } @names;
    my @discord = map { $discord->{$_} } @names;

    @names = map { ucfirst( substr( $_, 0, 4 ) ) } @names;

    my @data = ( \@names, \@results, \@discord );

    my $gd = $graph->plot(\@data) or die $graph->error;

    my $chart = 'public/charts/dpda-'. time() .'.png';
    open ( my $fh, '>', $chart ) or die "Can't write to $chart: $!";
    binmode $fh;
    print $fh $gd->png;
    close $fh;

    $chart =~ s/public\///;

    return $chart;
}

true;

__END__

=head1 SEE ALSO

L<Dancer2>

L<GD::Graph::bars>

=cut
