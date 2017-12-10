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

=head2 /

Redirect to C</overview>.

=cut

get '/' => sub {
    redirect '/overview';
};

=head2 /question

Question page.

Method: get

=cut

get '/question' => sub {
    my $progress = query_parameters->get('progress') || 1;

    # Handle the history
    my ( $history, %history );
    # Clear the history if on the first question
    if ( $progress == 1 ) {
        cookie( history => '' )
    }
    else {
        # Turn the history into an arrayref and a hash
        $history = cookie('history');
        if ( $history ) {
            $history = [ split /,/, $history ];
            %history = map { split /\|/, $_ } @$history;
        }
    }

    # Load the quiz questions
    my @quiz = _load_quiz();

    # Get a random question that has not been seen
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

    # Handle the history
    my $history = cookie('history');
    my %history;
    if ( $history || $answer ) {
        @history{ split /,/, $history } = undef;
        # Add the current response to the history
        $history{ "$question|$answer" } = undef;
        cookie( history => join( ',', keys %history ) );
    }

    # Increment the progress
    $progress++;

    # Load the quiz questions
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
    # Handle the history
    my $history = cookie('history');
    my %history;
    if ( $history ) {
        # Turn the history into an arrayref and a hash
        $history = [ split /,/, $history ];
        %history = map { split /\|/, $_ } @$history;
    }

    # Load the quiz questions
    my @quiz = _load_quiz();

    # Number of possible question responses
    my $responses = 10;

    # Perform the magical calculations...
    my ( %number, %order, %results, %average, %discord, $category );
    _calc_results( \@quiz, $responses, \%history, \%results, \%discord );
    _order_category( \%order, \@quiz );

    # Calculate the number of questions per category
    for $category ( keys %results ) {
        $number{$category} = grep { /^$category?.*$/ } @quiz;
    }

    # Calculate the average score for each category
    %average = map { $_ => $results{$_} / $number{$_} } keys %results;
    %average = map { $_ => sprintf( '%.2f', $average{$_} ) } keys %average;

    # Calculate the average discord between +/- questions
    %discord = map { $_ => ( $responses * $discord{$_} / ( $number{$_} / 2 ) ) / ( $responses - 1 ) } keys %discord;
    %discord = map { $_ => sprintf( '%.2f', $discord{$_} ) } keys %discord;

    # Render a results chart as an actual file
    my $chart = _draw_chart( $responses, \%order, \%average, \%discord );

    template 'chart' => {
        order   => \%order,
        average => \%average,
        discord => \%discord,
        chart   => $chart,
    };
};

=head2 /overview

Overview page.

=cut

get '/overview' => sub {
    template 'overview' => {};
};

=head2 /sample

Sample results page.

=cut


get '/sample' => sub {
    template 'sample' => {};
};

sub _load_quiz {
    my @quiz;

    my $file = 'public/dpda-questions.txt';

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

    # This should never happen:
    die 'History equal to number of questions'
        if keys(%$history) >= @$questions;

    # Get a question that has not been seen
    my $question_num;
    do {
        $question_num = int rand @$questions;
    }
    while exists $history->{$question_num};

    # Get the actual question and text
    my $question      = $questions->[$question_num];
    my $question_text = [ split /\|/, $question ]->[1];

    return $question_num, $question_text;
}

sub _calc_results {
    my ( $quiz, $responses, $history, $results, $discord ) = @_;

    my ( $category, $inv, $next );

    # Compute the results and discord from the history
    for my $key ( keys %$history ) {
        # Only consider every other history item
        next unless $key % 2;

        my $val = $history->{ $key - 1 };

        # Calculate with the question parameters
        ( $category, undef, $inv ) = split /\s+/, ( split /\|/, $quiz->[ $key - 1 ] )[0];

        $val = _invert_neg( $responses, $inv, $val );

        # Sum the category value
        $results->{$category} += $val;

        # ..And again for the next (discord) question
        $next = $history->{$key};
        $inv  = ( split /\s+/, ( split /\|/, $quiz->[$key] )[0] )[-1];
        $next = _invert_neg( $responses, $inv, $next );

        # Sum the category value
        $results->{$category} += $next;

        # Sum the discord category value
        $discord->{$category} += abs( $val - $next );
    }
}

sub _invert_neg {
    my ( $size, $flag, $val ) = @_;
    # Why?
    $flag eq '-' ? return $size - ($val - 1)
                 : return $val;
}

sub _order_category {
    my ( $order, $quiz ) = @_;

    my $next = 1;

    for my $category ( @$quiz ) {
        $category =~ s/^(\w+).*$/$1/;
        chomp $category;

        $order->{$category} = $next++
            unless exists $order->{$category};
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

    # Save the chart to an actual file
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
