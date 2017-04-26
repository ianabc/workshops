# Copyright (c) 2016 Banff International Research Station.
# This file is part of Workshops. Workshops is licensed under
# the GNU Affero General Public License as published by the
# Free Software Foundation, version 3 of the License.
# See the COPYRIGHT file for details and exceptions.

class EventsController < ApplicationController
  before_action :set_event, :set_attendance, only: [:show, :edit, :update, :destroy]
  before_filter :authenticate_user!, only: [:my_events, :new, :edit, :create, :update, :destroy]
  after_action :verify_policy_scoped, only: [:index, :past, :future, :kind]

  # GET /events
  # GET /events.json
  def index
    @events = policy_scope(Event)
    @heading = 'All Events'
  end

  # Get /events/mine
  def my_events
    @heading = 'My Events'
    @events = current_user.person.events.order(:start_date)
    render :index
  end

  # GET /events/past
  # GET /events/past.json
  def past
    @heading = 'Past Events'
    @events = policy_scope(Event).past.reverse_order
    render :index
  end

  # GET /events/future
  # GET /events/future.json
  def future
    @heading = 'Future Events'
    @events = policy_scope(Event).future
    render :index
  end

  # GET /events/year/:year
  # GET /events/year/:year.json
  def year
    year = params[:year]
    if year =~ /^\d{4}$/
      @heading = "#{year} Events"
      @events = policy_scope(Event).year(year)
      render :index
    else
      redirect_to events_path
    end
  end

  # GET /events/location/:location
  # GET /events/location/:location.json
  def location
    location = params[:location]
    unless Setting.Locations.keys.include?(location)
      location = Setting.Locations.keys.first
    end
    @heading = "Events at #{location}"
    @events = Event.location(location).order(:start_date)
    render :index
  end

  # GET /events/kind/:kind
  def kind
    kind = params[:kind].titleize
    if kind == 'Research In Teams'
      kind = 'Research in Teams'
    else
      unless Setting.Site['event_types'].include?(kind.singularize)
        kind = Setting.Site['event_types'].first
      end
    end

    @heading = kind.pluralize
    @events = policy_scope(Event).kind(kind)
    render :index
  end

  # GET /events/1
  # GET /events/1.json
  def show
    if @event
      authorize(@event) # only staff see template events
      @organizers = []
      @members = []
      @event.memberships.includes(:person).each do |member|
        @organizers << @event.member_info(member.person) if member.role =~ /Organizer/
        @members << @event.member_info(member.person) if member.attendance == 'Confirmed'
      end
      SyncEventMembersJob.perform_later(@event) if policy(@event).sync?
    else
      redirect_to root_path, error: 'No valid event specified.'
    end
  end

  # GET /events/new
  def new
    @event = Event.new
    authorize @event
  end

  # GET /events/1/edit
  def edit
    authorize @event
    @editable_fields = policy(@event).may_edit
    @edit_form = current_user.is_admin? ? 'admin_form' : 'member_form'
  end

  # POST /events
  # POST /events.json
  def create
    @event = Event.new(event_params)
    authorize @event

    respond_to do |format|
      if @event.save
        format.html { redirect_to @event, notice: 'Event was successfully created.' }
        format.json { render :show, status: :created, location: @event }
      else
        format.html { render :new }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /events/1
  # PATCH/PUT /events/1.json
  def update
    authorize @event

    original_event = @event.dup
    @editable_fields = policy(@event).may_edit
    @edit_form = current_user.is_admin? ? 'admin_form' : 'member_form'
    update_params = event_params.assert_valid_keys(*@editable_fields).merge(updated_by: current_user.name)

    respond_to do |format|
      if @event.update(update_params)
        notify_staff(event: original_event, params: update_params)
        format.html { redirect_to @event, notice: 'Event was successfully updated.' }
        format.json { render :show, status: :ok, location: @event }
      else
        format.html { render :edit }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /events/1
  # DELETE /events/1.json
  def destroy
    authorize @event
    @event.destroy
    respond_to do |format|
      format.html { redirect_to events_url, notice: 'Event was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

    def notify_staff(event: original_event, params: update_params)
      if params[:short_name] != event.short_name
        StaffMailer.nametag_update(original_event: event, args: params).deliver_now if event.is_upcoming?
      end

      if params[:description] != event.description || params[:press_release] != event.press_release
        StaffMailer.event_update(original_event: event, args: params).deliver_now
      end
    end

    def event_params
      params.require(:event).permit(:code, :name, :short_name, :start_date, :end_date, :time_zone, :event_type, :location, :description, :press_release, :max_participants, :door_code, :booking_code, :updated_by)
    end
end
