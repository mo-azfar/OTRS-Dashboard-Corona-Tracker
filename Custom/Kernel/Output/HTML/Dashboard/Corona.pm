# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --
package Kernel::Output::HTML::Dashboard::Corona;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::MaybeXS;
use HTML::Table;  # yum install -y perl-HTML-Table

# prevent 'Used once' warning
use Kernel::System::ObjectManager;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }
    
    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    return;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },
        # Don't cache this globally as it contains JS that is not inside of the HTML.
        CacheTTL => undef,
        CacheKey => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;
    
    my $Group = $Self->{Config}->{Group} || 0;
    my $CacheKey   = 'User' . '-' . $Self->{UserID} . '-' . $Group;

    # get cache object
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    my $Content = $CacheObject->Get(
        Type => 'DashboardCorona',
        Key  => $CacheKey,
    );
    #return to content cache so no need to refresh api
    return $Content if defined $Content; 
    
    my %Data = ();
    my $CountryCode = $Self->{Config}->{CountryCode};
    my $ua=LWP::UserAgent->new;

    my $response = $ua->request(
            GET "https://corona-api.com/countries/$CountryCode",
            Content_Type    => 'application/json'
        );
    
    my $ResponseData = decode_json $response->decoded_content;	
    #print Dumper $ResponseData;
    
    #TOTAL DATA
    my @HeadData1 = ('Country', 'Total Case', 'Total Recovered', 'Total Deaths', 'Active Case (Critical)');
    #create table header and format
	my $table1 = HTML::Table->new( 
    -cols    => scalar @HeadData1, 
	-class => 'corona',
    -head => [@HeadData1],
	);
    
    #if want use  table sections thead
    #$table1->addSectionRow ( 'thead', 0, 'Country', 'Total Case', 'Total Recovered', 'Total Deaths', 'Active Case (Critical)' );

    my $Total = $ResponseData->{data}->{latest_data};
    my $Active = $Total->{confirmed} - $Total->{recovered} - $Total->{deaths};
    $table1->addRow($ResponseData->{data}->{name}, $Total->{confirmed}, $Total->{recovered}, $Total->{deaths}, "$Active ($Total->{critical})"); 
    #push to template
    $Data{table1}=$table1;
    
    my $DateTimeObject = $Kernel::OM->Create(
        'Kernel::System::DateTime',
    );
    
    my $Now = $DateTimeObject->Format( Format => '%Y-%m-%d');
	my $GetOneDay = $DateTimeObject->Subtract( Days => 1,);
	my $OneDay = $DateTimeObject->Format( Format => '%Y-%m-%d');
    my $GetTwoDay = $DateTimeObject->Subtract( Days => 1,);
    my $TwoDay = $DateTimeObject->Format( Format => '%Y-%m-%d');
    my $GetThreeDay = $DateTimeObject->Subtract( Days => 1,);
    my $ThreeDay = $DateTimeObject->Format( Format => '%Y-%m-%d');
    
    my @Today = map {$_} grep { $_->{date} eq $Now } @{$ResponseData->{data}->{timeline}};
    my @PrevOne = map {$_} grep { $_->{date} eq $OneDay } @{$ResponseData->{data}->{timeline}};
    my @PrevTwo = map {$_} grep { $_->{date} eq $TwoDay } @{$ResponseData->{data}->{timeline}};
    
    #if the api not yet updated for today, assigned new date
    if (!@Today)
    {
        @Today = map {$_} grep { $_->{date} eq $OneDay } @{$ResponseData->{data}->{timeline}};
        @PrevOne = map {$_} grep { $_->{date} eq $TwoDay } @{$ResponseData->{data}->{timeline}};
        @PrevTwo = map {$_} grep { $_->{date} eq $ThreeDay } @{$ResponseData->{data}->{timeline}};
    }
    
    my @HeadData2 = ( 'Date', 'New Case', 'New Recovered', 'New Deaths');
    #create table header and format
	my $table2 = HTML::Table->new( 
    -cols    => scalar @HeadData2, 
	-class => 'corona',
    -head => [@HeadData2],
	);
    
    #check for cuurent day data by data->timeline and data->today
    if ( $Today[0]->{date} eq $Now && $ResponseData->{data}->{today}->{confirmed} ne $Today[0]->{new_confirmed} )
    {
        $Today[0]->{new_confirmed} = $ResponseData->{data}->{today}->{confirmed};
        $Today[0]->{new_recovered} = 'Updating ..';
        $Today[0]->{new_deaths} = $ResponseData->{data}->{today}->{deaths};
    }
    
    $table2->addRow($Today[0]->{date}, $Today[0]->{new_confirmed}, $Today[0]->{new_recovered}, $Today[0]->{new_deaths});
    $table2->addRow($PrevOne[0]->{date}, $PrevOne[0]->{new_confirmed}, $PrevOne[0]->{new_recovered}, $PrevOne[0]->{new_deaths});
    $table2->addRow($PrevTwo[0]->{date}, $PrevTwo[0]->{new_confirmed}, $PrevTwo[0]->{new_recovered}, $PrevTwo[0]->{new_deaths});
    #push to template
    $Data{table2}=$table2;
    
    # quote Title attribute, it will be used as name="" parameter of the iframe
    my $Title = $Self->{Config}->{Title} || '';
    $Title =~ s/\s/_/smx;

    $Content = $Kernel::OM->Get('Kernel::Output::HTML::Layout')->Output(
        TemplateFile => 'AgentDashboardCorona',
        Data         => \%Data,
    );

    # set cache result
    if ( $Self->{Config}->{CacheTTLLocal} ) {
        $CacheObject->Set(
            Type  => 'DashboardCorona',
            Key   => $CacheKey,
            Value => $Content || '',
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60 * 60, #set cache (if CacheTTLLocal = 1, means cache for 1 hour)
        );
    }
    
    return $Content;
}

1;
