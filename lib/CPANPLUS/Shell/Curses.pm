##################################################
###            CPANPLUS/Shell/Curses.pm        ###
### Module to provide a shell to the CPAN++    ###
###      Written 07-03-2003 by Marcus Thiesen  ###
##################################################

### Curses.pm ###

package CPANPLUS::Shell::Curses;
use strict;
use warnings;

BEGIN {
    use vars        qw( $VERSION @ISA);
    @ISA        =   qw( CPANPLUS::Shell::_Base );
    $VERSION    =   '0.01';
}

use CPANPLUS::Backend;
use CPANPLUS::I18N;

use Curses;
use Curses::UI 0.72;
use Pod::Text;
use File::Spec;
use File::chdir;
use Cwd;
use Module::ScanDeps;

###
### Key Bindings
### Most of them are default shell compatible
###
my $default_mode = {
    a   => "_search_author_init",
    b   => "_write_bundle",
    c   => "_show_reports_init",
    d   => "_fetch",
    e   => "_expand_inc_init",
    f   => "_search_dist_init",
    g   => "_draw",
    h   => "_pod_help",
    i   => "_install_install_init", # target => install
    j   => "_show_all",
    k   => "_display_installed",
    l   => "_goto_list",
    m   => "_search_module_init",
#   n reserved for next in search
    o   => "_uptodate",
    p   => "_print_stack",
    q   => "_quit", # also called on EOF and abnormal exits
    r   => "_readme",
    s   => "_set_conf",
    t   => "_install_test_init", # target => test
    u   => "_uninstall",
    v   => "_show_banner",
    w   => "_show_cache",
    x   => "_reload_indices",
    y   => "_show_perldoc", 
    z   => "_open_prompt",

   '!'  => "_eval_expr_init",
   '%'  => "_eval_shell_init",
#  '?' reserver for backward search
#  '/' reserver for search

    1   => "_fetch",
    2   => "_extract",
    3   => "_install_all_init", #target = all
    4   => "_install_test_init",
    5   => "_install_install_init",

    A => "_search_module_author",
    M => "_search_namespace_module",
    N => "_search_namespace_module2",
    R => "_show_installed",
    D => "_show_deps",
    S => "_show_stats"
};

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    ### Will call the _init constructor in Internals.pm ###
    my $self = $class->SUPER::_init( brand => loc('CPAN Terminal') );

    return $self;
}

### The CPAN Curses Interface
my $mainw;
my $cpanp;
my $data;
sub shell {
    ### Init CPANPLUS
    $cpanp = new CPANPLUS::Backend;
    my $config = $cpanp->configure_object();
    my $err  = $cpanp->error_object();

    $config->set_conf('verbose' => 1); ### Be quiet

    $data = $cpanp->module_tree();

    $config->set_conf('verbose' => 0); ### Be quiet

    if (not defined $data) { 
	die loc("FATAL: Couldn't get module list!\n") . $err->stack();
    }

    ### Init all the Curses...
    my $self = shift;
    $mainw = new Curses::UI('-clear_on_exit' => 1, '-mouse_support' => 0);

    $self->init_screen();

    my $list = $mainw->getobj('listw')->getobj('list');

    $mainw->draw();
    $mainw->status(loc("Loading..."));
    
    ### Apply the keybindings
    $list->set_routine("_quit", \&_quit );
    $list->set_routine("_show_banner", \&_show_banner);
    $list->set_routine("_help", \&_help);
    $list->set_routine("_search_author_init", \&_search_author_init);
    $list->set_routine("_search_module_init", \&_search_module_init);
    $list->set_routine("_goto_list", \&_goto_list);
    $list->set_routine("_install_install_init", \&_install_install_init);
    $list->set_routine("_install_test_init", \&_install_test_init);
    $list->set_routine("_readme", \&_readme);
    $list->set_routine("_draw", \&_draw);
    $list->set_routine("_search_dist_init", \&_search_dist_init);
    $list->set_routine("_fetch", \&_fetch);
    $list->set_routine("_uninstall", \&_uninstall);
    $list->set_routine("_display_installed", \&_display_installed);
    $list->set_routine("_show_all", \&_show_all);
    $list->set_routine("_expand_inc_init", \&_expand_inc_init);
    $list->set_routine("_uptodate", \&_uptodate);
    $list->set_routine("_set_conf", \&_set_conf);
    $list->set_routine("_eval_expr_init", \&_eval_expr_init);
    $list->set_routine("_show_cache", \&_show_cache);
    $list->set_routine("_pod_help", \&_pod_help);
    $list->set_routine("_show_perldoc", \&_show_perldoc);
    $list->set_routine("_print_stack", \&_print_stack);
    $list->set_routine("_reload_indices", \&_reload_indices);
    $list->set_routine("_open_prompt", \&_open_prompt);
    $list->set_routine("_write_bundle", \&_write_bundle);
    $list->set_routine("_show_reports_init", \&_show_reports_init);
    $list->set_routine("_extract_file", \&_extract_file);
    $list->set_routine("_eval_shell_init", \&_eval_shell_init);
    $list->set_routine("_install_all_init", \&_install_all_init);
    $list->set_routine("_search_module_author", \&_search_module_author);
    $list->set_routine("_search_namespace_module", \&_search_namespace_module);
    $list->set_routine("_search_namespace_module2", \&_search_namespace_module2);
    $list->set_routine("_extract", \&_extract);
    $list->set_routine("_show_installed", \&_show_installed);
    $list->set_routine("_show_deps", \&_show_deps);
    $list->set_routine("_show_stats", \&_show_stats);

    foreach my $key (keys %$default_mode) {
	$list->set_binding($default_mode->{$key}, $key);
    }
 
    _display_results($data);
    _show_installed();
    _goto_list();

    ###
    ### Main Loop
    ###
    $mainw->MainLoop;
}

sub leave_curses{ def_prog_mode(); endwin();}
sub reset_curses{ reset_prog_mode(); }

sub init_screen{
    my ($self, @args) = @_;
    my ($max_x, $max_y);

    $max_x = $mainw->height();
    $max_y = $mainw->width();
    
    ### So, let's do some naming conventions
    ### top window is "topw", status window is "statusw"
    ### the window in the left middle is "listw"
    ### and the window right middle is "displayw"
    ### "talk" is the label in "topw"
    ### "status" is the label in "statusw"
    my $top_height = 3;
    my $display_height = 7;
    my $listw_height =$max_x - $top_height - $display_height;

    my $topw = $mainw->add('topw','Window','-height' => $top_height, '-border' => 1, '-title' => loc('CPANPLUS CURSES SHELL'));

    my $listw = $mainw->add('listw','Window','-height' => $listw_height, '-border' => 1, 
			    '-y'=> $top_height);
	                                                 

    my $displayw = $mainw->add('displayw','Window','-height' => $display_height , '-border' => 1,
			       '-y'=> $top_height + $listw_height ,
                                ); 

    ### Some error checking
    $topw or warn "Couldn't create top window"; 
    $displayw or warn "Couldn't create display window"; 
    $listw or warn "Couldn't create listw window"; 

    my $talk = $topw->add('talk','Label');

    my $display = $displayw->add('display','TextViewer','-wrapping' => 1);

    my $list = $listw->add('list','Listbox','vscrollbar' => 'right', '-multi' => 1);
    $list->set_routine('_display_module_details',\&_display_module_details);
    $list->set_binding('_display_module_details', $list->KEY_ENTER());
    $list->onSelectionChange(\&_display_module_details);

    $talk or warn "Couldn't create talk label";

    $topw->focus();
}

### Ok, that's quite ugly, but blame Curses::UI
### We need sub to call from hotkey and one to
### get the input

sub _search_author_init{
    my $topw = $mainw->getobj('topw');

    my $text = loc("Author: ");

    $topw->getobj('talk')->text($text);
    $topw->add('input','TextEntry','-x' => length($text));
    $topw->getobj('input')->set_routine("loose-focus", \&_search_author);
    $topw->getobj('input')->set_binding("loose-focus", $mainw->KEY_ENTER());
    $topw->getobj('input')->focus();
}

sub _search_author{
    my $input = shift;

    $mainw->status(loc("Searching..."));
    $data = $cpanp->search(type => 'author', list=> [$input->get()], 'data' => $data);
    if (defined($data)) {
	_display_results($data);
	_show_installed();
    } else {
	$mainw->status(loc("Nothing found!"));
    }
    _input_cleanup();
}

sub _search_module_init{
    my $topw = $mainw->getobj('topw');

    my $text = loc("Module: ");

    $topw->getobj('talk')->text($text);
    $topw->add('input','TextEntry','-x' => length($text));
    $topw->getobj('input')->set_routine("loose-focus", \&_search_module);
    $topw->getobj('input')->set_binding("loose-focus", $mainw->KEY_ENTER());
    $topw->getobj('input')->focus();
}

sub _search_module{
    my $input = shift;
    $mainw->status(loc("Searching..."));
    $data = $cpanp->search(type => 'module', list=> [$input->get()], 'data' => $data);
    if (defined($data)) {
	_display_results($data);
	_show_installed();
    } else {
	$mainw->status(loc("Nothing found!"));
    }
    _input_cleanup();
}

sub _search_dist_init{
    my $topw = $mainw->getobj('topw');

    my $text = loc("Distribution: ");

    $topw->getobj('talk')->text($text);
    $topw->add('input','TextEntry','-x' => length($text));
    $topw->getobj('input')->set_routine("loose-focus", \&_search_dist);
    $topw->getobj('input')->set_binding("loose-focus", $mainw->KEY_ENTER());
    $topw->getobj('input')->focus();
}

sub _search_dist{
    my $input = shift;

    $mainw->status(loc("Searching..."));
    my $results = $cpanp->search(type => 'distribution', list=> [$input->get()]);
    if (defined($results)) {
	_display_results($results);
    } else {
	$mainw->status(loc("Nothing found!"));
    }
    _input_cleanup();
}


sub _readme{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $current_module = $list->get_active_value();
    my $err  = $cpanp->error_object();

    $mainw->status(loc('Getting readme for ') . $current_module);

    my $readme = $cpanp->readme('modules' => [$current_module]);

    unless ($readme->ok()) { 
	 _draw();
	 $mainw->error(loc("Could not get readme: ") . $err->stack());
	 return;
     } 

    my $text = $readme->rv->{$current_module}->{'readme'};

    return unless defined $text;
    return if ref $text;

    my $display = $mainw->add('readmew','Window'); 
			      
    my $viewer = $display->add('viewer','TextViewer',
			       '-border' => 1,	  
			       '-title' => loc("Readme for ") . $current_module);

    $viewer->text($text);
    $viewer->set_routine('_end_readme', \&_end_readme);
    $viewer->set_binding('_end_readme', "q" , " ");
    $viewer->draw();
    $viewer->focus();
}

sub _end_readme{
    my $display = $mainw->getobj('readmew');
    my $viewer  = $display->getobj('viewer');
    my $list = $mainw->getobj('listw')->getobj('list');

    $display->delete('viewer');
    $mainw->delete('readmew');
    
    $mainw->draw();
    $list->focus();
}

sub _show_installed{
    my $list = $mainw->getobj('listw')->getobj('list');

    ### Tell the user what lasts that long ;-)
    $mainw->status(loc('Loading installed...'));
    $list->clear_selection();

    ### First, get a sorted array of all installed mods
    my $installed = $cpanp->installed();
    my $mods = $installed->{'rv'};
    my %looktbl;
    foreach my $mod (keys %$mods) { $looktbl{$mod}++; }

    ### Create an ordered list of all displayed modules
    my @all_modlist = sort keys %$data;

    my $index = 0;

    foreach my $imod (@all_modlist) {
	$list->set_selection($index) if defined $looktbl{$imod};
	$index++;
    }
}

sub _fetch{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $installed = $cpanp->installed();
    my $mods = $installed->{'rv'};
    my @instmods = sort keys %$mods;
    my $current_module = $list->get_active_value();
    my @selection = $list->get();

    my %look_tbl;
    my @to_fetch;

    foreach my $item (@instmods) {$look_tbl{$item} = 1; }
    foreach my $item (@selection) {
	unless ($look_tbl{$item}) {
	    push @to_fetch, $item;
    }}

    my $err = $cpanp->error_object();

    push @to_fetch, $current_module unless (@to_fetch > 0);
    my @endmessage;

    foreach my $mod (@to_fetch) {
	$mainw->status(loc('Currently fetching ') . $mod);
		my $iresult = $cpanp->fetch(modules => [$mod]);
	if ($iresult->ok()) {
	    _draw();
	    push @endmessage, $mod . loc(" fetched successfully");
	} else {
	    _draw();
	   push @endmessage, loc("Error fetching ") . $mod . "\n" . $err->stack();
	}
	_draw();
    }
    $mainw->dialog(join("\n",@endmessage));
    _show_installed();
}

sub _extract {
    my $list = $mainw->getobj('listw')->getobj('list');
    my $installed = $cpanp->installed();
    my $mods = $installed->{'rv'};
    my @instmods = sort keys %$mods;
     my $current_module = $list->get_active_value();

    my @selection = $list->get();

    my %look_tbl;
    my @to_fetch;

    foreach my $item (@instmods) {$look_tbl{$item} = 1; }
    foreach my $item (@selection) {
	unless ($look_tbl{$item}) {
	    push @to_fetch, $item;
    }}

    my $err = $cpanp->error_object();
    push @to_fetch, $current_module unless (@to_fetch > 0);
    my @endmessage;
    foreach my $mod (@to_fetch) {
	$mainw->status(loc('Currently fetching ') . $mod);
	my $iresult = $cpanp->fetch(modules => [$mod]);
	if ($iresult->ok()) {
	    _draw();
	    $mainw->status(loc('Currently extracting ') . $mod);
	    $data->{$mod}->extract();
	} else {
	    _draw();
	   push @endmessage,loc("Error extracting ") . $mod . "\n" . $err->stack();
	}
	_draw();
    }
    _show_installed();
    $mainw->dialog(join("\n",@endmessage)) if (@endmessage > 0);
}

sub _install_install_init{
    _install("install");
}

sub _install_test_init{
    _install("test");
}

sub _install_all_init{
    _install("all");
}

sub _install{ 
    my $target = shift;
    my $list = $mainw->getobj('listw')->getobj('list');
    my $installed = $cpanp->installed();
    my $mods = $installed->{'rv'};
    my $current_module = $list->get_active_value();
    my @instmods = sort keys %$mods;

    my @selection = $list->get();

    my %look_tbl;
    my @to_install;

    foreach my $item (@instmods) {$look_tbl{$item} = 1; }
    foreach my $item (@selection) {
	unless ($look_tbl{$item}) {
	    push @to_install, $item;
	}
    }


    my $err = $cpanp->error_object();
    ###
    ### Here follows some bad magic in order to try to get the input 
    ### any install script may want from us:
    my @endmessage;

    push @to_install, $current_module unless (@to_install > 0);
   
    leave_curses();

    print loc("Went back to shell to install: ") . "\n" . join("\n", @to_install);
    print "\n";
   
    foreach my $mod (@to_install) {

	my $iresult = $cpanp->install(modules => [$mod], 'target' => $target);

	if ($iresult->ok()) {
	    push @endmessage, $mod . loc(" installed successfully");
	} else {
	    push @endmessage, loc("Error installing ") . $mod . "\n" . $err->stack();
	}
    }
    _show_installed();	
    _draw();
    reset_curses();
    $mainw->dialog(join("\n", @endmessage));
}

sub _uninstall{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $installed = $cpanp->installed();
    my $mods = $installed->{'rv'};
    my @instmods = sort keys %$mods;
    my $current_module = $list->get_active_value();
    my @selection = $list->get();


    my %look_tbl;
    my @to_uninstall;

    foreach my $item (@selection) {
	$look_tbl{$item}++; 
    }
 
    foreach my $item (@instmods) {
	if ((!defined($look_tbl{$item})) && (defined($data->{$item}))) {
	    push @to_uninstall, $item;
	}
    }

    my $err = $cpanp->error_object();

    push @to_uninstall, $current_module unless (@to_uninstall > 0);

    _draw();
    my @warning = (
       loc('Note that uninstall only uninstalls the module you ask for '),
       loc('It does not track prerequisites for you, nor will it warn you if'),
       loc('you uninstall a module another module depends on!'),
       loc('Are you sure that you want to uninstall the following module(s):')
	       );

    my $yes = $mainw->dialog('-message' => join("\n", (@warning, @to_uninstall)),
			     '-buttons' => [ 'yes','no'],
			     '-values'  => [1, 0],
			     '-title'   => loc('Warning'));

    if ($yes == 0) {
	$list->clear_selection();
	_show_installed();
	return;
	}		     

    my @endmessage;
    foreach my $mod (@to_uninstall) {
	$mainw->status(loc('Currently uninstalling ') . $mod);
	my $iresult = $cpanp->uninstall(modules => [$mod]);
	if ($iresult->ok()) {
	    push @endmessage, $mod . loc(" removed successfully");
	} else {
	   push @endmessage, loc("Error removing ") . $mod . "\n" . $err->stack();
	}
    }
    _show_installed();
    _draw();
    $mainw->dialog(join("\n", @endmessage));

}

sub _display_installed{
    my $installed = $cpanp->installed();
    my $instmods = $installed->{'rv'};
    my %newdata;
    foreach my $module (keys %$instmods) {
	$newdata{$module} = $data->{$module};
    }
    $data = \%newdata;
    _display_results();
    _show_installed();
}

sub _show_all{
    $data = $cpanp->module_tree();
    _display_results();
    _show_installed();
}

sub _expand_inc_init{
    my $topw = $mainw->getobj('topw');

    my $text = loc("Path to add:");

    $topw->getobj('talk')->text($text);
    $topw->add('input','TextEntry','-x' => length($text));
    $topw->getobj('input')->set_routine("loose-focus", \&_expand_inc);
    $topw->getobj('input')->set_binding("loose-focus", $mainw->KEY_ENTER());
    $topw->getobj('input')->focus();
}

sub _expand_inc{
    my $input = shift;

    push @INC, $input->get() if defined $input->get();
    _input_cleanup();
}

###
### This is rather ugly, but we need to know which packages
### where scheduled for update

sub _uptodate{
    $mainw->status(loc('Looking for updated modules...'));
    my $installed = $cpanp->installed();
    my $instmods = $installed->{'rv'};
    my %newdata;
    foreach my $module (keys %$instmods) {
	my $uptodate = $cpanp->uptodate('modules' => [$module]);
	next unless defined $uptodate;
	next if $uptodate->rv()->{$module}->{uptodate};
	$newdata{$module} = $data->{$module};
    }
    $data = \%newdata;
    
    my $list = $mainw->getobj('listw')->getobj('list');
    
    $list->set_routine('leave-update', \&leave_update);
    $list->set_binding('leave-update', keys %$default_mode);
    $list->set_routine('abort-update', \&abort_update);
    $list->set_binding('abort-update', 'q');

    my @message = (
		   loc('Select all packages you want to update, then hit any key to install updates'),
		   loc('To abort, press q')
		   );
    _draw();
    $mainw->dialog(join("\n",@message));

    _display_results();
    $list->clear_selection();
}

sub leave_update{
    my $list = $mainw->getobj('listw')->getobj('list');
    my @selection = $list->get();    
    my $err = $cpanp->error_object();
    leave_curses();
    print loc("Went back to shell to update ") . "\n";
    print join "\n", @selection;
    print "\n";

    my @endmessage;
    foreach my $mod (@selection) {

	my $iresult = $cpanp->install(modules => [$mod], 
				      target => 'install');

	if ($iresult->ok()) {
	    push @endmessage, $mod . loc(" updated successfully");
	} else {

	   push @endmessage, loc("Error updates ") . $mod . "\n" . $err->stack();
	}
   }
    foreach my $key (keys %$default_mode) {
	$list->set_binding($default_mode->{$key}, $key);
    }
    _show_all();
    _show_installed();	
    reset_curses();
    $mainw->dialog(join("\n", @endmessage));
}

sub abort_update{
    my $list = $mainw->getobj('listw')->getobj('list');
    _show_all();

    foreach my $key (keys %$default_mode) {
	$list->set_binding($default_mode->{$key}, $key);
    }
}

sub _eval_expr_init{
    my $topw = $mainw->getobj('topw');

    my $text = loc("Perl Expression:");

    $topw->getobj('talk')->text($text);
    $topw->add('input','TextEntry','-x' => length($text));
    $topw->getobj('input')->set_routine("loose-focus", \&_eval_expr);
    $topw->getobj('input')->set_binding("loose-focus", $mainw->KEY_ENTER());
    $topw->getobj('input')->focus();
}

sub _eval_expr{
    my $input = shift;
    my $expr = $input->get();

    $mainw->status(loc("Executing..."));
    eval($expr);
    _input_cleanup();
    _draw();
}

sub _eval_shell_init{
    my $topw = $mainw->getobj('topw');

    my $text = loc("Shell Expression:");

    $topw->getobj('talk')->text($text);
    $topw->add('input','TextEntry','-x' => length($text));
    $topw->getobj('input')->set_routine("loose-focus", \&_eval_shell);
    $topw->getobj('input')->set_binding("loose-focus", $mainw->KEY_ENTER());
    $topw->getobj('input')->focus();
}

sub _eval_shell{
    my $input = shift;
    my $expr = $input->get();

    leave_curses();
    system($expr);

    reset_curses();
    _input_cleanup();
    _draw();
}

sub _show_cache{
    _display_results();
    _show_installed();
}

sub _quit{
    $mainw->status(loc("Exiting..."));
    exit 0;
}

sub _display_results{
    my $values = (shift  || $data);
    my @displaymod = sort(keys(%$values));

    $mainw->getobj('listw')->getobj('list')->values(\@displaymod);
    $mainw->getobj('listw')->getobj('list')->draw();
}

sub _input_cleanup{
    my $topw = $mainw->getobj('topw');

    $topw->getobj('input')->loose_focus();
    $topw->delete('input');
    $topw->getobj('talk')->text("");
    $mainw->getobj('listw')->getobj('list')->focus;
}

sub _goto_list{
    $mainw->getobj('listw')->getobj('list')->focus();
}

sub _display_module_details{
    my $list = $mainw->getobj('listw')->getobj('list');

    my $current_module = $list->get_active_value();
    return unless defined $current_module;

    my $details = $data->{$current_module};
    return unless defined $details;

    my @text;
    push @text, loc("Name:    ") . $current_module;
    push @text, loc("Version: ") . $details->{'version'};
    push @text, loc("Author:  ") . $details->{'author'};
    push @text, loc("Path:    ") . $details->{'path'};
    push @text, loc("Package: ") . $details->{'package'};
   
    $mainw->getobj('displayw')->getobj('display')->text(join("\n", @text));
    $mainw->getobj('displayw')->getobj('display')->draw;
}

sub _set_conf{
    my $config = $cpanp->configure_object();

    my @conf_options = $config->subtypes('conf');

    ### Build us a nice config window
    my $max_x = $mainw->height();
    my $max_y = $mainw->width();
    my $height = $max_x-1;
    my $width = int $max_y / 2;
    $height = @conf_options unless @conf_options > $max_x -2;
    $height+=2;

    my $configw = $mainw->add('configw','Window','-border' => 1, '-width' => $width,
			      '-height' => $height, '-centered' => 1,
			      '-title' => loc('CPANPLUS Configuration')
			      );
    my $posy = 0;
    my $posx = 0;
    # Find which option has the lonest name
    foreach my $opt (@conf_options) { 
	$posx = length($opt) unless length($opt) <= $posx
	}
    $posx++;

    foreach my $opt (@conf_options) {
	$configw->add($opt . 'l', 'Label', '-y' => $posy,
		      '-text' => "\u$opt:");


	if (ref $config->get_conf($opt) eq "HASH") {
	    my $hashref = $config->get_conf($opt);
	    my @keys = keys %$hashref;
	    my @values = values %$hashref;
	    my $text;
	    foreach my $key (@keys) {
		$text .= $key . "=" . $hashref->{$key} . ":";
	    }
	    $configw->add($opt . 'hl', 'Label', '-y' => $posy, 
			  '-x' => 3);

	    my $entry = $configw->add($opt . 'he', 'TextEntry', 
				      '-y' => $posy, 
				      '-x' => $posx);
	    $entry->text($text);
	    $entry->set_routine('_store_conf', \&_store_conf);
	    $entry->set_binding('_store_conf', $mainw->KEY_ENTER() );
	}
	elsif (ref $config->get_conf($opt) eq "ARRAY") {
	    my $arrayref = $config->get_conf($opt);
	    my $text = join (":", @$arrayref);
	    my $entry = $configw->add($opt . 'ae', 'TextEntry', 
				      '-y' => $posy, 
				      '-x' => $posx);
	    $entry->text($text);
	    $entry->set_routine('_store_conf', \&_store_conf);
	    $entry->set_binding('_store_conf', $mainw->KEY_ENTER() );
	}
	else {
	    my $entry = $configw->add($opt . 'e', 'TextEntry', '-y' => $posy, 
				      '-x' => $posx);

	    my $text = $config->get_conf($opt);
	    if (defined($text)) {
		if ($text eq "1") { $text = 'Y' }
		if ($text eq "0") { $text = 'N' }
		$entry->text($text);
	    }
	    $entry->set_routine('_store_conf', \&_store_conf);
	    $entry->set_binding('_store_conf', $mainw->KEY_ENTER() );
	}
	$posy++;
    }
    $configw->focus();
}

sub _store_conf{
    my $configw = $mainw->getobj('configw');
    my $config = $cpanp->configure_object();

    my @conf_options = $config->subtypes('conf');
    foreach my $opt (@conf_options) {
	my $entry = $configw->getobj($opt . 'e');
	if (defined $entry) {
	    my $text = $entry->get();
	    next unless defined $text;
	    $opt = "\l$opt";

	    $text =~ s/^Y.*/1/i;
	    $text =~ s/^N.*/0/i;
	    $config->set_conf($opt => $text); }
	else {
	    my $entry = $configw->getobj($opt . 'ae');
	    if (defined $entry) {
		my @values = split(":", $entry->get());
		$config->set_conf($opt => \@values);
	    }
	    else {
	    	my $entry = $configw->getobj($opt . 'he');
		if (defined $entry) {
		    my @values = split(":", $entry->get());
		    my %hash_values;
		    foreach my $value (@values) {
			my ($key, $value) = split "=", $value;
			$hash_values{$key} = $value;
		    }
		    $config->set_conf($opt => \%hash_values);
		}
	    }
	}
    }
    my $filename = $ENV{'PERL5_CPANPLUS_CONFIG'};

    my $yes = $mainw->dialog('-message' => loc("Do you want to store the settings to " . $filename . "?"),
			     '-buttons' => [ 'yes','no'],
			     '-values'  => [1, 0],
			     '-title'   => loc('Qustion'));

    ### There is a bug in current Configure.pm and the docs,
    ### it doesn't save the config as it was meant to.
    unless ($config->can_save($filename)) {
	_draw();
	$mainw->error(loc("You are not allowed to write to ") 
		      . $filename . "\n" .
		      loc("Config will be discared after exit"));
    } else {

	$config->save($filename) if ($yes);
    }

    $mainw->getobj('configw')->loose_focus();
    $mainw->delete('configw');
    $mainw->getobj('listw')->getobj('list')->focus();

    ###
    ### Somewhere here something odd happens, the curses
    ### appears in the list. No workaround till now, 
    ### maybe a bug in Curses::UI
}

sub _draw{
    ### This is some bad curses magic in order to
    ### get my screen back
    $mainw->add('dummy','Window');
    $mainw->getobj('dummy')->draw();
    $mainw->delete('dummy');

    $mainw->getobj('topw')->draw();
    $mainw->getobj('displayw')->draw();
    $mainw->getobj('listw')->draw();
    $mainw->draw();
}

###
### Help and version info
###
sub _pod_help{
    my $podparser = Pod::Text->new(sentence => 0);

    my $filename;

    ### Find myself
    foreach my $mod (keys %INC) {
	$filename  = $INC{$mod} if ($mod =~ /Curses\.pm/);
    }

    my $text = `pod2text $filename`;

    my $display = $mainw->add('readmew','Window');
    my $viewer = $display->add('viewer','TextViewer');


    $viewer->text($text);
    $viewer->set_routine('_end_readme', \&_end_podhelp);
    $viewer->set_binding('_end_readme', "q" , " ");
    $viewer->draw();
    $viewer->focus();
}

sub _end_podhelp{
    my $display = $mainw->getobj('readmew');
    my $viewer  = $display->getobj('viewer');
    my $list = $mainw->getobj('listw')->getobj('list');

    $display->delete('viewer');
    $mainw->delete('readmew');

    $mainw->draw();
    $list->focus();
}

sub _print_stack{
    my $err = $cpanp->error_object();
    my @errors = $err->stack();

    if (@errors == 0) {
	push @errors, loc("No errors occured yet");
    }
    _draw();
    $mainw->dialog(join("\n",@errors) );
}

sub _show_perldoc{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $current_module = $list->get_active_value();
    my $err  = $cpanp->error_object();

    my $installed = $cpanp->installed();
    my $instmods = $installed->{'rv'};

    return unless defined $instmods->{$current_module};


    my $text = `pod2text $instmods->{$current_module}`;

    my $display = $mainw->add('readmew','Window');
    my $viewer = $display->add('viewer','TextViewer', '-border' => 1,	  
			       '-title' => loc("Perldoc for ") . $current_module);

    return unless defined $text;

    $viewer->text($text);
    $viewer->set_routine('_end_readme', \&_end_podhelp);
    $viewer->set_binding('_end_readme', "q" , " ");
    $viewer->draw();
    $viewer->focus();
}

sub _reload_indices{
    $mainw->status(loc('Reloading CPAN indices...'));
    my $err  = $cpanp->error_object();

    my $result = $cpanp->reload_indices('update_source' => 1);
    _draw();
    if ($result) {
	$mainw->dialog(loc('Successfully reloaded CPAN indices!'));
    } else {
	$mainw->error(loc('An error occured during reload: ') ."\n" . $err->stack());
    }
}

sub _open_prompt{
    my $config = $cpanp->configure_object();

    my $shell = $config->get_conf('prompt') || $ENV{'SHELL'} ||  "/bin/sh";

    my $list = $mainw->getobj('listw')->getobj('list');

    my $current_module = $list->get_active_value();
    return unless defined $current_module;

    my $details = $data->{$current_module};
    return unless defined $details;

    $mainw->status(loc('Extracting ') . $current_module);
    local $CWD = $details->extract();
    $mainw->nostatus();
    if ($shell) {
	leave_curses();
	my $oldps1 = $ENV{PS1};
	$ENV{PS1} = "CPANPLUS::Shell::Curses\$ ";

	print loc("Type exit to return to CPANPLUS::Shell::Curses\n");
	print loc("You are in $CWD\n");
	system ($ENV{SHELL});

	reset_curses();
	$ENV{PS1} = $oldps1;
    }
}

sub _write_bundle{
    my $err  = $cpanp->error_object();
    $mainw->status(loc('Writing a autobundle...'));

    my $rv = $cpanp->autobundle();
    _draw();
    if ($rv->ok()) {
	my $name = $rv->rv();
	$mainw->dialog(loc("Auobundle ") . $name . loc(" successfully written"));
    } else {
	$mainw->error(loc('An error occured during bundling: ') ."\n" . $err->stack());
    } 
}

sub _show_reports_init{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $current_module = $list->get_active_value();
    my $err  = $cpanp->error_object();

    next unless $current_module;

    $mainw->status(loc('Getting reports for ') . $current_module);

    my $reports = $cpanp->reports('modules' => [$current_module]);

    unless ($reports->ok()) { 
	 _draw();
	 $mainw->error(loc("Could not get report: ") . $err->stack());
	 return;
     } 
    my @text;
    my $rvref = $reports->rv();
    return unless $rvref;
    my $arrayref = $rvref->{$current_module};
    return unless $arrayref;
    foreach my $hashref (@$arrayref) {
	foreach my $key (keys %$hashref) {
	    push @text, "\u$key: " . $hashref->{$key};
	}
	push @text, " ";
    }

    $mainw->dialog(message => join("\n",@text),
		   title => loc("Test results for ") . $current_module );
}

sub _extract_files{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $installed = $cpanp->installed();
    my $mods = $installed->{'rv'};
    my @instmods = sort keys %$mods;
 
    my @selection = $list->get();

    my %look_tbl;
    my @to_extract;

    foreach my $item (@instmods) {$look_tbl{$item} = 1; }
    foreach my $item (@selection) {
	unless ($look_tbl{$item}) {
	    push @to_extract, $item;
    }}

    my $err = $cpanp->error_object();

    foreach my $mod (@to_extract) {
	$mainw->status(loc('Currently extracting') . $mod);
	my $iresult = $cpanp->extract(modules => [$mod]);
	if ($iresult->ok()) {
	    _draw();
	    $mainw->dialog($mod . loc(" extracted successfully"));
	} else {
	    _draw();
	   $mainw->error(loc("Error extracting ") . $mod . "\n" . $err->stack());
	}
	_draw();
    }


}

sub _show_banner{

    my @text = ( 
		 loc('                  CPANPLUS::SHELL::Curses                    '),
		 loc('        Visual CPAN exploration and module installation      '),     
		 loc('    Please report bugs to <marcus@cpan.thiesenweb.de>. '),
		 loc(' Using CPANPLUS::Backend v0.050.  ReadLine support enabled.  ')
		 );
    _draw();
    $mainw->dialog(join("\n",@text));
}


sub _search_module_author{
    $mainw->status(loc("Searching..."));
    my $list = $mainw->getobj('listw')->getobj('list');

    my $current_module = $list->get_active_value();
    return unless defined $current_module;

    my $details = $data->{$current_module};
    return unless defined $details;

    my $author = $details->{'author'};
    return unless defined $author;
    $mainw->status(loc("Searching for ") . $author );

    $data = $cpanp->search(type => 'author', list=> [$author]);
    if (defined($data)) {
	_display_results($data);
	_show_installed();
    } else {
	$mainw->status(loc("Nothing found!"));
    }
}

sub _search_namespace_module{
    $mainw->status(loc("Searching..."));
    my $list = $mainw->getobj('listw')->getobj('list');

    my $current_module = $list->get_active_value();
    return unless defined $current_module;

    if ($current_module =~ /(\w+)/) {
	my $namespace = $1;
	$mainw->status(loc("Searching in Namespace ") . $namespace);
	$data = $cpanp->search(type => 'module', list=> ["^$namespace"]);
	if (defined($data)) {
	    _display_results($data);
	    _show_installed();
	} else {
	    $mainw->status(loc("Nothing found!"));
	}
    }
    $mainw->nostatus();
}

sub _search_namespace_module2{
    $mainw->status(loc("Searching..."));
    my $list = $mainw->getobj('listw')->getobj('list');

    my $current_module = $list->get_active_value();
    return unless defined $current_module;

    if ($current_module =~ /(\w+::\w+)/) {
	my $namespace = $1;
	$mainw->status(loc("Searching in Namespace ") . $namespace);
	$data = $cpanp->search(type => 'module', list=> ["^$namespace"]);
	if (defined($data)) {
	    _display_results($data);
	    _show_installed();
	} else {
	    $mainw->status(loc("Nothing found!"));
	}
    }
    $mainw->nostatus();
}

sub _show_deps{
    my $list = $mainw->getobj('listw')->getobj('list');
    my $current_module = $list->get_active_value();
    my $err  = $cpanp->error_object();

    my $installed = $cpanp->installed();
    my $instmods = $installed->{'rv'};

    return unless defined $instmods->{$current_module};

    $mainw->status(loc("Searching dependencies for ") .  $current_module);

    my $hashref = Module::ScanDeps::scan_deps($instmods->{$current_module});

    my @modules = keys %$hashref;
    my @names;

    foreach my $module (@modules) {
	$module =~ s|/|::|g;
	$module =~ s/\.pm|\.ix|\.al|\.ld|\.so|\.bs//g;
	push @names, $module;
    }
    @names = sort @names;
    $mainw->dialog(-message => join("\n",@names), 
		   -title => loc("Dependencies for ") . $current_module);
}

sub _show_stats{
    $mainw->status(loc("Gathering statistical information..."));
    my $installed = $cpanp->installed();
    my $instmods = $installed->{'rv'};
    my $modules = $cpanp->module_tree();
    my $authors = $cpanp->author_tree();
    my $number_outdated = 0;
    foreach my $module (keys %$instmods) {
	my $uptodate = $cpanp->uptodate('modules' => [$module]);
	next unless defined $uptodate;
	next if $uptodate->rv()->{$module}->{uptodate};
	$number_outdated++;
    }

    my $number_installed = keys %{$instmods};
    my $number_total = keys %{$modules};
    my $number_authors = keys %{$authors};

    $mainw->dialog( loc('Installed Modules: ') . $number_installed . "\n"
		   .loc('Outdated Module: ') . $number_outdated . "\n\n"
		   .loc('Modules on CPAN: ') . $number_total . "\n"
		   .loc('Registered Authors: ') . $number_authors . "\n\n"
		   .loc('PID: ') . $$ . "\n"
		   .loc('OS: ') . $^O . "\n"
		   .loc('Perl Version: ') . $] . "\n"
		    );
}


1;

__END__

=pod

=head1 NAME

CPANPLUS::Shell::Curses - A Curses based shell for CPANPLUS

=head1 ABSTRACT

CPANPLUS::Shell::Curses is a graphical user interface
to the newly developed CPANPLUS package

=head1 USAGE

Usually all operations will be performed on the currently
selected and/or marked Module.
Searching is done as incremental search, so first author then
module gives you other results than first module than author.
Reset searching/display with j.

I<For installing and updating the Shell leaves Curses mode.
At the moment this is considered a feature, in order to answer
module's questions about configuration.>

=head1 KEYS


=head2 General

h      detailed help                 
            
q      exit                                      

v      version information                       

=head2 Search

a      search by author(s)

A      search modules by the author of the 
       currently active module

m      search by module(s)

M      search modules in the same top level
       Namespace as the currently active
       one (i.e. if CPAN is active it will show
       you only modules CPAN::*)

N      search modules in the same top and second
       level namespace as the currently active
       one  (i.e. AI::Categorizer is active it
       will show you only the ones under AI::Categorizer)

o      update check

j      display all modules

k      diplay installed modules

w      show search cache

=head2 List window functions

/       does a search in the list window
        as well in the readme and help viewers

?       does it the other way around

^C-A    go to the beginning (also with HOME)

^C-E    go to end of list (also with END)

PGDOWN  one page down

PGUP    one page up

=head2 Operations

i      install selected module(s)

u      uninstall selected module(s)

d      download selected module(s)

r      display readme of active module

c      display test results for active module

y      show perldoc of currently selected
       installed module

b      write an autobundle of all your 
       currently installed modules   

z      open command prompt 

R      reload installed selection

=head2 Local Administration

!      eval a Perl expression

%      execute a shell expression

g      redraw screen

e      add directories to your @INC

s      set configuration options for this session

p      print error stack

r      reload CPAN indices

D      show currently installed modules dependencies

S      show some statistical information

=head2 Step by Step

For easy stepping through the installation 
steps, shortcuts are provided:
   
1      fetch modules

2      extract modules (not implemented yet)

3      make all

4      make test

5      make install

=head1 CONFIGURATION

To enter the configuration window, type 's'.
All values which are either yes or no are shown with
a Y or N value. To change this value just enter what you
want it to be. ;-)
Some special input is required for the options Makeflags,
Makemakerflage and lib.
The syntax for Makeflags and Makemakerflags is C<key=value>,
multiple keys can be seperated by C<:>
The syntax for Lib is a C<:> seperated list of lib 
directories.

=head1 TODO

=over 4

=item
Updating isn't that nice as it could be.

=item
Testing it on other platforms

=back

=head1 BUGS

=over 4

=item

Curses.pm 1.06 does not compile with Perl 5.8.0, a new release
that fixes those bugs is expected soon

=item

It is too slow :-)

=item

Documentation needed

=item

As it is a development version based on a development version
of CPANPLUS please test it against the latest devel version
of CPANPLUS. Afterwards feel free to contact me about any bugs.

=back

=head1 AUTHOR

Marcus Thiesen (marcus@cpan.thiesenweb.de)

=head1 SEE ALSO

L<CPANPLUS>
L<Curses>
L<Curses::UI>
L<ncurses>
L<perl>


=cut
