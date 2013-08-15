class NotesController < ApplicationController

  respond_to :html
  before_filter :require_user, :only => [:create, :edit, :update]

  def index
    @title = "Research notes"
    set_sidebar
  end

  def tools
    @title = "Tools"
    @notes = DrupalNode.paginate(:conditions => {:status => 1, :type => 'tool'}, :order => "node_counter.totalcount DESC", :include => :drupal_node_counter, :page => params[:page])
    render :template => "notes/tools_places"
  end

  def places
    @title = "Places"
    @notes = DrupalNode.paginate(:conditions => {:status => 1, :type => 'place'}, :order => "node_counter.totalcount DESC", :include => :drupal_node_counter, :page => params[:page])
    render :template => "notes/tools_places"
  end

  def show
    if params[:author] && params[:date]
      @node = DrupalUrlAlias.find_by_dst('notes/'+params[:author]+'/'+params[:date]+'/'+params[:id])
      @node = DrupalUrlAlias.find_by_dst('report/'+ params[:id]) if @node.nil?
      @node = @node.node if @node.node 
    else
      @node = DrupalNode.find params[:id]
    end
    if @node.author.status == 0 && !(current_user && (current_user.role == "admin" || current_user.role == "moderator"))
      flash[:error] = "The author of that note has been banned."
      redirect_to "/"
    end 

    # if it's spam or a draft
    if @node.status != 1 && !(current_user && (current_user.role == "admin" || current_user.role == "moderator"))
      # no notification; don't let people easily fish for existing draft titles; we should try to 404 it
      redirect_to "/"
    end
 
    @node.view
    @title = @node.title
    @tags = @node.tags
    @tagnames = @tags.collect(&:name)

    set_sidebar :tags, @tagnames
  end

  def create
    if current_user.drupal_user.status == 1
      saved,@node,@revision = DrupalNode.new_note({
        :uid => current_user.uid,
        :title => params[:title],
        :body => params[:body],
        :main_image => params[:main_image]
      })
      if saved
        params[:tags].split(',').each do |tagname|
          @node.add_tag(tagname,current_user)
        end
        # trigger subscription notifications:
        SubscriptionMailer.notify_node_creation(@node)
        # opportunity for moderation
        flash[:notice] = "Research note published."
        flash[:notice] = "Research note published. Get the word out on <a href='/wiki/mailing-lists'>the discussion lists</a>."
        redirect_to @node.path
      else
        render :template => "editor/post"
      end
    else
      flash.keep[:error] = "You have been banned. Please contact <a href='mailto:web@publiclab.org'>web@publiclab.org</a> if you believe this is in error."
      redirect_to "/logout"
    end
  end

  def edit
    @node = DrupalNode.find(params[:id],:conditions => {:type => "note"})
    if current_user.uid == @node.uid || current_user.username == "warren" # || current_user.role == "admin" 
      render :template => "editor/post"
    else
      prompt_login "Only the author can edit a research note."
    end
  end

  # at /notes/update/:id
  def update
    @node = DrupalNode.find(params[:id])
    if current_user.uid == @node.uid || current_user.username == "warren" # || current_user.role == "admin" 
      @revision = @node.latest
      @revision.title = params[:title]
      @revision.body = params[:body]
      if @revision.valid?
        @revision.save
        @node.vid = @revision.vid
        if @node.drupal_main_image
          i = @node.drupal_main_image
          i.vid = @revision.vid 
          i.save
        end
        @node.drupal_content_field_image_gallery.each do |img|
          img.vid = @revision.vid
          img.save
        end
        @node.title = @revision.title
        # save main image
        if params[:main_image] && params[:main_image] != ""
          img = Image.find params[:main_image]
          img.nid = @node.id
          img.save
        end
        @node.save!
        flash[:notice] = "Edits saved."
        redirect_to @node.path
      else
        flash[:error] = "Your edit could not be saved."
        render :action => :edit
      end
    end
  end

  # at /notes/delete/:id
  # only for notes
  def delete
    @node = DrupalNode.find(params[:id])
    if current_user.uid == @node.uid && @node.type == "note" || current_user.role == "admin" || current_user.role == "moderator"
      @node.delete
      respond_with do |format|
        format.html do
          if request.xhr?
            render :text => "Content deleted."
          else
            flash[:notice] = "Content deleted."
            redirect_to "/dashboard"
          end
        end
      end
    else
      prompt_login
    end
  end

  # notes for a given author
  def author
    @user = DrupalUsers.find_by_name params[:id]
    @title = @user.name
    @notes = DrupalNode.paginate(:order => "nid DESC", :conditions => {:type => 'note', :status => 1, :uid => @user.uid}, :page => params[:page])
    render :template => 'notes/index'
  end

  # notes for given comma-delimited tags params[:topic] for author
  def author_topic
    @user = DrupalUsers.find_by_name params[:author]
    @tagnames = params[:topic].split('+')
    @title = @user.name+" on '"+@tagnames.join(', ')+"'"
    @notes = @user.notes_for_tags(@tagnames)
    @unpaginated = true
    render :template => 'notes/index'
  end

  # notes with high # of likes
  def liked
    @title = "Highly liked research notes"
    @wikis = DrupalNode.find(:all, :limit => 10, :conditions => {:type => 'page', :status => 1}, :order => "nid DESC")
    @notes = DrupalNode.find(:all, :limit => 20, :order => "cached_likes DESC", :conditions => {:type => 'note', :status => 1})
    @unpaginated = true
    render :template => 'notes/index'
  end

  # notes with high # of views
  def popular
    @title = "Popular research notes"
    @wikis = DrupalNode.find(:all, :limit => 10, :conditions => {:type => 'page', :status => 1}, :order => "nid DESC")
    @notes = DrupalNode.find(:all, :limit => 20, :order => "node_counter.totalcount DESC", :conditions => {:type => 'note', :status => 1}, :include => :drupal_node_counter)
    @unpaginated = true
    render :template => 'notes/index'
  end

  def rss
    @notes = DrupalNode.find(:all, :limit => 20, :order => "nid DESC", :conditions => {:type => 'note', :status => 1})
    respond_to do |format|
      format.rss {
        render :layout => false
        response.headers["Content-Type"] = "application/xml; charset=utf-8"
      } 
    end
  end

end
