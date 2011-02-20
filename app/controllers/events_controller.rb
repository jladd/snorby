class EventsController < ApplicationController
  respond_to :html, :xml, :json, :js, :csv
  helper_method :sort_column, :sort_direction

  def index
    @events = Event.order(sort_column + " " + sort_direction).view_format(params).all.paginate(:page => params[:page], :per_page => User.current_user.per_page_count)
    @classifications ||= Classification.all
  end

  def queue
    @events ||= @current_user.events.joins(:ip,:signature).order(sort_column + " " + sort_direction).all.paginate(:page => params[:page], :per_page => User.current_user.per_page_count)
    @classifications ||= Classification.all
  end

  def request_packet_capture
    @event = Event.get(params['sid'], params['cid'])
    @packet = @event.packet_capture(params)
    respond_to do |format|
      format.html {render :layout => false}
      format.js
    end
  end

  def show
    @event = Event.includes(:ip,:signature,:sensor,:tcp,:udp,:notes,:icmp).find(params['sid'], params['cid'])
    @notes = @event.notes.all.paginate(:page => params[:page], :per_page => 5, :order => 'id DESC', :include => [:user])
    respond_to do |format|
      format.html {render :layout => false}
      format.js
      format.pdf do
        render :pdf => "Event:#{@event.id}", :template => "events/show.pdf.erb", :layout => 'pdf.html.erb', :stylesheets => ["pdf"]
      end
      format.xml { render :xml => @event.in_xml }
      format.csv { render :text => @event.to_csv }
      format.json { render :json => @event.in_json }
    end
  end

  def view
    @events = Event.where(:sid => params['sid'], :cid => params['cid']).all.paginate(:page => params[:page], :per_page => User.current_user.per_page_count)
    @classifications ||= Classification.all
  end

  def create_email
    @event = Event.find(params[:sid], params[:cid])
    render :layout => false
  end

  def email
    Delayed::Job.enqueue(Snorby::Jobs::EventMailerJob.new(params[:sid], params[:cid], params[:email]))
    respond_to do |format|
      format.html { render :layout => false }
      format.js
    end
  end

  def create_mass_action
    @event = Event.find(params[:sid], params[:cid])
    render :layout => false
  end

  def mass_action
    options = {}

    params[:reclassify] ? (reclassify = true) : (reclassify = false)

    if params.has_key?(:sensor_ids)
      options.merge!({:sid => params[:sensor_ids].map(&:to_i)}) if params[:sensor_ids].is_a?(Array)
    end

    options.merge!({:sig_id => params[:sig_id].to_i}) if params[:use_sig_id]

    options.merge!({:"ip.ip_src" => IPAddr.new(params[:ip_src].to_i,Socket::AF_INET)}) if params[:use_ip_src]

    options.merge!({:"ip.ip_dst" => IPAddr.new(params[:ip_dst].to_i,Socket::AF_INET)}) if params[:use_ip_dst]

    if options.empty?
      render :js => "flash_message.push({type: 'error', message: 'Sorry, Insufficient classification parameters submitted...'});flash();"
    else
      Delayed::Job.enqueue(Snorby::Jobs::MassClassification.new(params[:classification_id], options, User.current_user.id, reclassify))
      respond_to do |format|
        format.html { render :layout => false }
        format.js
      end
    end
  end

  def export
    @events = Event.find_by_ids(params[:events])

    respond_to do |format|
      format.json { render :json => @events }
      format.xml { render :xml => @events }
      format.csv { render :json => @events.to_csv }
    end
  end

  def history
    @events = Event.all(:user_id => @current_user.id).page(params[:page].to_i, :per_page => @current_user.per_page_count, :order => [:timestamp.desc])
    @classifications ||= Classification.all
  end

  def classify
    @events = Event.find_by_ids(params[:events])
    Rails.logger.debug @events    
    Event.classify_from_collection(@events, params[:classification].to_i, User.current_user.id, true)
    render :layout => false, :status => 200
  end

  def mass_create_favorite
    @events ||= Event.find_by_ids(params[:events])
    @events.each { |event| event.create_favorite unless favorite? }
    render :json => {}
  end

  def mass_destroy_favorite
    @events ||= Event.find_by_ids(params[:events])
    @events.each { |event| event.destroy_favorite if favorite? }
    render :json => {}
  end

  def last
    render :json => {:time => Event.last.timestamp}
  end

  def since
    @events = Event.to_json_since(params[:timestamp])
    render :json => @events.to_json
  end

  def favorite
    @event = Event.find(params[:sid], params[:cid])
    @event.toggle_favorite
    render :json => {}
  end

  def lookup
    if Setting.lookups?
      @lookup = Snorby::Lookup.new(params[:address])
      render :layout => false
    else
      render :text => '<div id="note-box">This feature has be disabled</div>'.html_safe, :notice => 'This feature has be disabled'
    end
  end

  def activity
    @user = User.find(params[:user_id])
    @events = @user.events.page(params[:page].to_i, :per_page => @current_user.per_page_count, :order => [:timestamp.desc])
    @classifications ||= Classification.all
  end

  def hotkey
    @classifications ||= Classification.all
    respond_to do |format|
      format.html {render :layout => false}
      format.js
    end
  end

  def packet_capture
    @event = Event.find(params[:sid], params[:cid])
    render :layout => false
  end

  private

    def sort_column
      columns = ['sid', 'cid', 'ip_src', 'ip_dst', 'severity', 'signature', 'sig_priority', 'timestamp']
      columns.include?(params[:sort]) ? params[:sort] : 'timestamp'
    end

    def sort_direction
      %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"
    end

end
